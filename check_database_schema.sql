-- ============================================
-- Database Schema Check
-- ============================================
-- Run this first to see your actual table structure

-- Check user_profiles table structure
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'user_profiles'
ORDER BY ordinal_position;

-- Check deliveries table structure  
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'deliveries'
ORDER BY ordinal_position;

-- Check vehicle_types table structure
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'vehicle_types'
ORDER BY ordinal_position;

-- Check driver_profiles table structure
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'driver_profiles'
ORDER BY ordinal_position;