-- PostgreSQL Test Database Setup
-- Run this with: psql -U postgres -f setup_test_db.sql

-- Create test database
DROP DATABASE IF EXISTS zigorm_test;
CREATE DATABASE zigorm_test;

-- Connect to test database
\c zigorm_test

-- Verify connection
SELECT 'PostgreSQL test database created successfully!' AS status;

-- You can now run: zig build test
-- The PostgreSQL tests will connect to: postgresql://postgres:root123@localhost:5432/zigorm_test
