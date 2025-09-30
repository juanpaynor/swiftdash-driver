-- ============================================
-- SwiftDash Driver App - Simplified RLS Fix
-- ============================================
-- More permissive policies that allow signup to work

-- 1. USER_PROFILES - Allow signup without strict auth checks
-- ============================================

-- Drop all existing policies
DROP POLICY IF EXISTS "Users can insert own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can read own profile" ON user_profiles; 
DROP POLICY IF EXISTS "Users can update own profile" ON user_profiles;
DROP POLICY IF EXISTS "authenticated_insert" ON user_profiles;
DROP POLICY IF EXISTS "authenticated_select" ON user_profiles;
DROP POLICY IF EXISTS "authenticated_update" ON user_profiles;

-- Enable RLS
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Simple policies that work during signup
CREATE POLICY "Allow all authenticated inserts" ON user_profiles
FOR INSERT TO authenticated
WITH CHECK (true);

CREATE POLICY "Users can read own profile" ON user_profiles
FOR SELECT TO authenticated
USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON user_profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id);

-- 2. DRIVER_PROFILES - Allow signup without strict auth checks
-- ============================================

-- Drop all existing policies
DROP POLICY IF EXISTS "Drivers can insert own profile" ON driver_profiles;
DROP POLICY IF EXISTS "Drivers can read own profile" ON driver_profiles;
DROP POLICY IF EXISTS "Drivers can update own profile" ON driver_profiles;
DROP POLICY IF EXISTS "driver_insert" ON driver_profiles;
DROP POLICY IF EXISTS "driver_select" ON driver_profiles;
DROP POLICY IF EXISTS "driver_update" ON driver_profiles;

-- Simple policies that work during signup
CREATE POLICY "Allow all authenticated driver inserts" ON driver_profiles
FOR INSERT TO authenticated
WITH CHECK (true);

CREATE POLICY "Drivers can read own profile" ON driver_profiles
FOR SELECT TO authenticated
USING (auth.uid() = id);

CREATE POLICY "Drivers can update own profile" ON driver_profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id);

-- 3. Keep vehicle_types readable
-- ============================================
-- This should already work, but just in case
DROP POLICY IF EXISTS "Anyone can read vehicle types" ON vehicle_types;

ALTER TABLE vehicle_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read vehicle types" ON vehicle_types
FOR SELECT TO authenticated
USING (is_active = true);