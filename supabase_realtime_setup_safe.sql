-- ============================================
-- SAFE Supabase Realtime Configuration SQL
-- ============================================
-- This version checks existing configuration before making changes

-- 1. CHECK CURRENT REALTIME STATUS
-- ============================================
-- See which tables are already enabled for realtime
SELECT 'Current realtime tables:' as info;
SELECT schemaname, tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
ORDER BY tablename;

-- 2. SAFELY ENABLE REALTIME ON TABLES
-- ============================================
-- Only add tables that aren't already in the publication

-- Check and add deliveries (skip if already exists)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'deliveries'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE deliveries;
        RAISE NOTICE 'Added deliveries table to realtime publication';
    ELSE
        RAISE NOTICE 'deliveries table already in realtime publication';
    END IF;
END
$$;

-- Check and add driver_profiles
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'driver_profiles'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE driver_profiles;
        RAISE NOTICE 'Added driver_profiles table to realtime publication';
    ELSE
        RAISE NOTICE 'driver_profiles table already in realtime publication';
    END IF;
END
$$;

-- Check and add user_profiles
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'user_profiles'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE user_profiles;
        RAISE NOTICE 'Added user_profiles table to realtime publication';
    ELSE
        RAISE NOTICE 'user_profiles table already in realtime publication';
    END IF;
END
$$;

-- Check and add vehicle_types
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'vehicle_types'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE vehicle_types;
        RAISE NOTICE 'Added vehicle_types table to realtime publication';
    ELSE
        RAISE NOTICE 'vehicle_types table already in realtime publication';
    END IF;
END
$$;

-- 3. CHECK FINAL REALTIME STATUS
-- ============================================
SELECT 'Final realtime tables:' as info;
SELECT schemaname, tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
AND tablename IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
ORDER BY tablename;

-- 4. VERIFY RLS POLICIES EXIST
-- ============================================
SELECT 'Current RLS policies:' as info;
SELECT tablename, policyname, cmd, permissive
FROM pg_policies 
WHERE tablename IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
ORDER BY tablename, policyname;

-- 5. TEST REALTIME READINESS
-- ============================================
SELECT 'Realtime readiness check:' as info;
SELECT 
    t.tablename,
    CASE 
        WHEN p.tablename IS NOT NULL THEN 'Realtime ENABLED ✅'
        ELSE 'Realtime DISABLED ❌'
    END as realtime_status,
    CASE 
        WHEN t.rowsecurity THEN 'RLS ENABLED ✅'
        ELSE 'RLS DISABLED ❌'
    END as rls_status
FROM pg_tables t
LEFT JOIN pg_publication_tables p ON p.tablename = t.tablename AND p.pubname = 'supabase_realtime'
WHERE t.tablename IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
AND t.schemaname = 'public'
ORDER BY t.tablename;