-- ============================================
-- SwiftDash Driver App - RLS Policies Fix
-- ============================================
-- Run this SQL in your Supabase SQL Editor to fix signup issues

-- 1. USER_PROFILES TABLE POLICIES
-- ============================================

-- Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Users can insert own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can read own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON user_profiles;

-- Enable RLS on user_profiles (if not already enabled)
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to insert their own profile during signup
CREATE POLICY "Users can insert own profile" ON user_profiles
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = id);

-- Allow users to read their own profile
CREATE POLICY "Users can read own profile" ON user_profiles
FOR SELECT TO authenticated
USING (auth.uid() = id);

-- Allow users to update their own profile
CREATE POLICY "Users can update own profile" ON user_profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- 2. DRIVER_PROFILES TABLE POLICIES
-- ============================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Drivers can insert own profile" ON driver_profiles;
DROP POLICY IF EXISTS "Drivers can read own profile" ON driver_profiles;
DROP POLICY IF EXISTS "Drivers can update own profile" ON driver_profiles;

-- Enable RLS on driver_profiles (if not already enabled)
ALTER TABLE driver_profiles ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to insert their own driver profile
CREATE POLICY "Drivers can insert own profile" ON driver_profiles
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = id);

-- Allow drivers to read their own profile
CREATE POLICY "Drivers can read own profile" ON driver_profiles
FOR SELECT TO authenticated
USING (auth.uid() = id);

-- Allow drivers to update their own profile (for status changes, etc.)
CREATE POLICY "Drivers can update own profile" ON driver_profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- 3. VEHICLE_TYPES TABLE POLICIES
-- ============================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Anyone can read vehicle types" ON vehicle_types;

-- Enable RLS on vehicle_types (if not already enabled)
ALTER TABLE vehicle_types ENABLE ROW LEVEL SECURITY;

-- Allow anyone (authenticated) to read vehicle types (for signup dropdown)
CREATE POLICY "Anyone can read vehicle types" ON vehicle_types
FOR SELECT TO authenticated
USING (is_active = true);

-- 4. DELIVERIES TABLE POLICIES (for future use)
-- ============================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Drivers can read own deliveries" ON deliveries;
DROP POLICY IF EXISTS "Drivers can update own deliveries" ON deliveries;

-- Enable RLS on deliveries (if not already enabled)
ALTER TABLE deliveries ENABLE ROW LEVEL SECURITY;

-- Allow drivers to read deliveries assigned to them
CREATE POLICY "Drivers can read own deliveries" ON deliveries
FOR SELECT TO authenticated
USING (driver_id = auth.uid());

-- Allow drivers to update deliveries assigned to them (status changes)
CREATE POLICY "Drivers can update own deliveries" ON deliveries
FOR UPDATE TO authenticated
USING (driver_id = auth.uid())
WITH CHECK (driver_id = auth.uid());

-- 5. VERIFICATION QUERIES
-- ============================================

-- Check if policies were created successfully
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies 
WHERE tablename IN ('user_profiles', 'driver_profiles', 'vehicle_types', 'deliveries')
ORDER BY tablename, policyname;