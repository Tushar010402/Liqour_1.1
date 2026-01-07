-- Migration: Add salary field to users table
-- Purpose: Track salary information for all user roles (admin, manager, salesman, etc.)
-- Date: 2025-10-14

-- Add salary column to users table (nullable, for optional salary tracking)
ALTER TABLE users
ADD COLUMN IF NOT EXISTS salary DECIMAL(12, 2) DEFAULT NULL;

-- Add comment to document the column purpose
COMMENT ON COLUMN users.salary IS 'Monthly or annual salary for the user (optional, stored in tenant currency)';

-- Create index for salary-based queries (e.g., payroll reports)
CREATE INDEX IF NOT EXISTS idx_users_salary ON users(salary) WHERE salary IS NOT NULL;
