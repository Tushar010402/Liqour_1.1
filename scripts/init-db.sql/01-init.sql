-- LiquorPro Fresh Database Initialization Script
-- This script creates a clean, fresh database for LiquorPro SaaS application

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create database if not exists (this is handled by Docker)
-- CREATE DATABASE IF NOT EXISTS liquorpro;

-- Use the database
\c liquorpro;

-- Clear any existing data (fresh start)
DO $$ 
DECLARE 
    r RECORD;
BEGIN
    -- Drop all tables if they exist
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') 
    LOOP
        EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE';
    END LOOP;
    
    -- Drop all sequences if they exist
    FOR r IN (SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public')
    LOOP
        EXECUTE 'DROP SEQUENCE IF EXISTS ' || quote_ident(r.sequence_name) || ' CASCADE';
    END LOOP;
    
    -- Drop all functions if they exist
    FOR r IN (SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_type = 'FUNCTION')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || quote_ident(r.routine_name) || ' CASCADE';
    END LOOP;
END $$;

-- Create fresh schema
-- Note: Tables will be created by the Go application migration system
-- This ensures we have a completely clean database

-- Log the initialization
INSERT INTO pg_catalog.pg_stat_statements_info (dealloc) VALUES (0) ON CONFLICT DO NOTHING;

-- Final message
DO $$
BEGIN
    RAISE NOTICE 'LiquorPro Fresh Database Initialized Successfully';
    RAISE NOTICE 'Database: %', current_database();
    RAISE NOTICE 'Timestamp: %', now();
END $$;