-- ============================================
-- Supabase Realtime Configuration SQL
-- ============================================
-- Run this in your Supabase SQL Editor to enable realtime properly

-- 1. ENABLE REALTIME ON TABLES
-- ============================================
-- These commands enable realtime for the required tables
ALTER PUBLICATION supabase_realtime ADD TABLE deliveries;
ALTER PUBLICATION supabase_realtime ADD TABLE driver_profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE user_profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE vehicle_types;

-- 2. UPDATE RLS POLICIES FOR REALTIME ACCESS
-- ============================================

-- DELIVERIES TABLE - Allow realtime access
-- Drop and recreate policies to ensure realtime compatibility
DROP POLICY IF EXISTS "Customers can read own deliveries" ON deliveries;
DROP POLICY IF EXISTS "Drivers can read assigned deliveries" ON deliveries;
DROP POLICY IF EXISTS "Drivers can update assigned deliveries" ON deliveries;

-- Enable RLS if not already enabled
ALTER TABLE deliveries ENABLE ROW LEVEL SECURITY;

-- Allow customers to read their own deliveries (for realtime)
CREATE POLICY "Customers can read own deliveries" ON deliveries
FOR SELECT TO authenticated
USING (customer_id = auth.uid());

-- Allow drivers to read deliveries assigned to them (for realtime)
CREATE POLICY "Drivers can read assigned deliveries" ON deliveries
FOR SELECT TO authenticated
USING (driver_id = auth.uid() OR status = 'pending');

-- Allow drivers to update assigned deliveries
CREATE POLICY "Drivers can update assigned deliveries" ON deliveries
FOR UPDATE TO authenticated
USING (driver_id = auth.uid() OR (driver_id IS NULL AND status = 'pending'))
WITH CHECK (driver_id = auth.uid());

-- Allow system to insert deliveries (from edge functions)
CREATE POLICY "System can insert deliveries" ON deliveries
FOR INSERT TO authenticated
WITH CHECK (true);

-- DRIVER_PROFILES TABLE - Allow realtime access
-- Drop and recreate policies
DROP POLICY IF EXISTS "Drivers can read own profile" ON driver_profiles;
DROP POLICY IF EXISTS "Drivers can update own profile" ON driver_profiles;
DROP POLICY IF EXISTS "Public can read driver info" ON driver_profiles;

-- Allow drivers to read their own profile
CREATE POLICY "Drivers can read own profile" ON driver_profiles
FOR SELECT TO authenticated
USING (auth.uid() = id);

-- Allow drivers to update their own profile
CREATE POLICY "Drivers can update own profile" ON driver_profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- Allow customers to read basic driver info for assigned deliveries
CREATE POLICY "Customers can read assigned driver info" ON driver_profiles
FOR SELECT TO authenticated
USING (
  id IN (
    SELECT driver_id FROM deliveries 
    WHERE customer_id = auth.uid() 
    AND driver_id IS NOT NULL
  )
);

-- Allow drivers to insert their own profile (signup)
CREATE POLICY "Drivers can insert own profile" ON driver_profiles
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = id);

-- USER_PROFILES TABLE - Already configured but ensure realtime access
-- These should already exist from your previous setup

-- VEHICLE_TYPES TABLE - Allow reading for all authenticated users
DROP POLICY IF EXISTS "Anyone can read vehicle types" ON vehicle_types;

CREATE POLICY "Anyone can read vehicle types" ON vehicle_types
FOR SELECT TO authenticated
USING (is_active = true);

-- 3. VERIFY REALTIME SETUP
-- ============================================
-- Check if tables are properly configured for realtime
SELECT schemaname, tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
AND tablename IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types');

-- Check RLS policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd
FROM pg_policies 
WHERE tablename IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
ORDER BY tablename, policyname;