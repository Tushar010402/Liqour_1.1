-- Migration: 046_add_unique_phone_constraint.sql
-- Description: Add UNIQUE constraint on phone column to prevent duplicate phone numbers
-- Date: 2025-12-02
-- Author: System fix for duplicate phone issue

-- Add unique constraint on phone column
-- This ensures phone numbers are unique across all tenants (globally unique)
-- Required for OTP-based authentication to work correctly
ALTER TABLE users ADD CONSTRAINT uq_users_phone UNIQUE (phone);

-- Note: This migration was already applied directly to fix a critical bug
-- where the same phone number existed for users in different tenants,
-- causing cross-tenant login issues.
