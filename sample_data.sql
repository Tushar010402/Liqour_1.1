-- Insert sample tenants using correct column names
INSERT INTO tenants (id, name, is_active, created_at, updated_at) 
VALUES 
('373e965a-6dec-44d6-a2ab-0400449fc71d', 'LiquorPro Demo', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('b1234567-89ab-cdef-0123-456789abcdef', 'ABC Liquor Store', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('c2345678-9abc-def0-1234-56789abcdef0', 'XYZ Wine Shop', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('d3456789-abcd-ef01-2345-6789abcdef01', 'Premium Spirits', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('e4567890-bcde-f012-3456-789abcdef012', 'Local Liquor', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (name) DO NOTHING;

-- Add SaaS admin user using correct column names
INSERT INTO users (id, tenant_id, username, first_name, last_name, email, phone, password_hash, role, is_active, created_at, updated_at) 
VALUES 
('saas-admin-001', NULL, 'saas_admin', 'SaaS', 'Admin', 'admin@liquorpro.com', '+918630668488', '$2a$10$example.hash.for.password123', 'saas_admin', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('user-demo-001', '373e965a-6dec-44d6-a2ab-0400449fc71d', 'demo_user', 'Demo', 'User', 'demo@liquorpro.com', '+918630668489', '$2a$10$example.hash.for.password123', 'admin', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (username) DO NOTHING;

-- Insert sample shops
INSERT INTO shops (id, tenant_id, name, address, phone, is_active, created_at, updated_at) 
VALUES 
(gen_random_uuid(), '373e965a-6dec-44d6-a2ab-0400449fc71d', 'Main Store', '123 Main St, City', '+919876543210', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(gen_random_uuid(), 'b1234567-89ab-cdef-0123-456789abcdef', 'ABC Downtown', '456 Oak Ave, Town', '+919876543211', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(gen_random_uuid(), 'c2345678-9abc-def0-1234-56789abcdef0', 'XYZ Center', '789 Pine Rd, Village', '+919876543212', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Add some sample categories and brands
INSERT INTO categories (tenant_id, name, description) 
VALUES 
('373e965a-6dec-44d6-a2ab-0400449fc71d', 'Whiskey', 'Premium whiskey collection'),
('373e965a-6dec-44d6-a2ab-0400449fc71d', 'Wine', 'Fine wines and champagnes'),
('373e965a-6dec-44d6-a2ab-0400449fc71d', 'Beer', 'Local and imported beers');

INSERT INTO brands (tenant_id, name, description) 
VALUES 
('373e965a-6dec-44d6-a2ab-0400449fc71d', 'Royal Stag', 'Premium Indian whiskey'),
('373e965a-6dec-44d6-a2ab-0400449fc71d', 'McDowell', 'Popular Indian spirit brand'),
('373e965a-6dec-44d6-a2ab-0400449fc71d', 'Kingfisher', 'Leading beer brand');

-- Success message
SELECT 'Sample data inserted successfully!' as status;