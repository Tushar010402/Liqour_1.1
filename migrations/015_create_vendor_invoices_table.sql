-- Create vendor_invoices table for accounts payable tracking
CREATE TABLE IF NOT EXISTS vendor_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    vendor_id UUID NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
    invoice_number VARCHAR(100) NOT NULL,
    invoice_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE NOT NULL,
    total_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    paid_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    due_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- pending, partial, paid, overdue
    description TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_vendor_invoices_tenant_id ON vendor_invoices(tenant_id);
CREATE INDEX IF NOT EXISTS idx_vendor_invoices_vendor_id ON vendor_invoices(vendor_id);
CREATE INDEX IF NOT EXISTS idx_vendor_invoices_status ON vendor_invoices(status);
CREATE INDEX IF NOT EXISTS idx_vendor_invoices_due_date ON vendor_invoices(due_date);
CREATE INDEX IF NOT EXISTS idx_vendor_invoices_deleted_at ON vendor_invoices(deleted_at);
CREATE INDEX IF NOT EXISTS idx_vendor_invoices_due_amount ON vendor_invoices(due_amount) WHERE due_amount > 0;

-- Unique constraint for invoice number per tenant
CREATE UNIQUE INDEX IF NOT EXISTS uni_vendor_invoices_invoice_number
ON vendor_invoices(tenant_id, invoice_number) WHERE deleted_at IS NULL;

-- Create trigger for updated_at timestamp
CREATE OR REPLACE FUNCTION update_vendor_invoices_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_vendor_invoices_updated_at
BEFORE UPDATE ON vendor_invoices
FOR EACH ROW
EXECUTE FUNCTION update_vendor_invoices_updated_at();

-- Trigger to automatically calculate due_amount and update status
CREATE OR REPLACE FUNCTION update_vendor_invoice_due_amount()
RETURNS TRIGGER AS $$
BEGIN
    -- Calculate due amount
    NEW.due_amount = NEW.total_amount - NEW.paid_amount;

    -- Update status based on payment
    IF NEW.paid_amount >= NEW.total_amount THEN
        NEW.status = 'paid';
    ELSIF NEW.paid_amount > 0 THEN
        NEW.status = 'partial';
    ELSIF NEW.due_date < CURRENT_DATE THEN
        NEW.status = 'overdue';
    ELSE
        NEW.status = 'pending';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_vendor_invoice_due_amount
BEFORE INSERT OR UPDATE ON vendor_invoices
FOR EACH ROW
EXECUTE FUNCTION update_vendor_invoice_due_amount();

-- Add comment to table
COMMENT ON TABLE vendor_invoices IS 'Vendor invoices for accounts payable tracking and financial reporting';
