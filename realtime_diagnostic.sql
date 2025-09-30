-- ============================================
-- REALTIME DIAGNOSTIC SCRIPT
-- ============================================
-- Run this in Supabase SQL Editor to check if realtime is working properly

-- 1. CHECK REALTIME PUBLICATION STATUS
-- ============================================
SELECT 
    '🔍 REALTIME PUBLICATION STATUS' as check_type,
    '' as table_name,
    '' as status,
    '' as details;

SELECT 
    'realtime_tables' as check_type,
    tablename as table_name,
    '✅ ENABLED' as status,
    'Table is published for realtime' as details
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
AND tablename IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
UNION ALL
SELECT 
    'realtime_tables' as check_type,
    t.table_name as table_name,
    '❌ MISSING' as status,
    'Table is NOT published for realtime' as details
FROM information_schema.tables t
WHERE t.table_schema = 'public'
AND t.table_name IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
AND t.table_name NOT IN (
    SELECT tablename FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime'
)
ORDER BY table_name;

-- 2. CHECK ROW LEVEL SECURITY STATUS
-- ============================================
SELECT 
    '🔒 ROW LEVEL SECURITY STATUS' as check_type,
    '' as table_name,
    '' as status,
    '' as details;

SELECT 
    'rls_status' as check_type,
    schemaname || '.' || tablename as table_name,
    CASE 
        WHEN rowsecurity THEN '✅ ENABLED'
        ELSE '❌ DISABLED'
    END as status,
    'RLS must be enabled for secure realtime access' as details
FROM pg_tables
WHERE schemaname = 'public'
AND tablename IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
ORDER BY tablename;

-- 3. CHECK RLS POLICIES
-- ============================================
SELECT 
    '📋 RLS POLICIES STATUS' as check_type,
    '' as table_name,
    '' as status,
    '' as details;

SELECT 
    'rls_policies' as check_type,
    tablename as table_name,
    '✅ ' || cmd as status,
    policyname as details
FROM pg_policies 
WHERE tablename IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
ORDER BY tablename, policyname;

-- 4. CHECK TABLE DATA EXISTS
-- ============================================
SELECT 
    '📊 TABLE DATA STATUS' as check_type,
    '' as table_name,
    '' as status,
    '' as details;

-- Check deliveries
SELECT 
    'table_data' as check_type,
    'deliveries' as table_name,
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ HAS DATA (' || COUNT(*) || ' rows)'
        ELSE '⚠️ EMPTY'
    END as status,
    'Delivery records for testing' as details
FROM deliveries;

-- Check driver_profiles
SELECT 
    'table_data' as check_type,
    'driver_profiles' as table_name,
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ HAS DATA (' || COUNT(*) || ' rows)'
        ELSE '⚠️ EMPTY'
    END as status,
    'Driver profiles for authentication' as details
FROM driver_profiles;

-- Check vehicle_types
SELECT 
    'table_data' as check_type,
    'vehicle_types' as table_name,
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ HAS DATA (' || COUNT(*) || ' rows)'
        ELSE '⚠️ EMPTY'
    END as status,
    'Vehicle types for delivery options' as details
FROM vehicle_types;

-- 5. REALTIME READINESS SUMMARY
-- ============================================
SELECT 
    '🎯 REALTIME READINESS SUMMARY' as check_type,
    '' as table_name,
    '' as status,
    '' as details;

SELECT 
    'readiness_summary' as check_type,
    t.tablename as table_name,
    CASE 
        WHEN p.tablename IS NOT NULL AND t.rowsecurity THEN '🟢 READY'
        WHEN p.tablename IS NOT NULL AND NOT t.rowsecurity THEN '🟡 REALTIME OK, RLS DISABLED'
        WHEN p.tablename IS NULL AND t.rowsecurity THEN '🟡 RLS OK, REALTIME DISABLED'
        ELSE '🔴 NOT READY'
    END as status,
    CASE 
        WHEN p.tablename IS NOT NULL AND t.rowsecurity THEN 'Ready for secure realtime'
        WHEN p.tablename IS NOT NULL AND NOT t.rowsecurity THEN 'Need to enable RLS'
        WHEN p.tablename IS NULL AND t.rowsecurity THEN 'Need to add to realtime publication'
        ELSE 'Need both RLS and realtime publication'
    END as details
FROM pg_tables t
LEFT JOIN pg_publication_tables p ON p.tablename = t.tablename AND p.pubname = 'supabase_realtime'
WHERE t.schemaname = 'public'
AND t.tablename IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
ORDER BY t.tablename;

-- 6. CURRENT AUTH USER CHECK
-- ============================================
SELECT 
    '👤 AUTHENTICATION CHECK' as check_type,
    '' as table_name,
    '' as status,
    '' as details;

SELECT 
    'auth_check' as check_type,
    'current_user' as table_name,
    CASE 
        WHEN auth.uid() IS NOT NULL THEN '✅ AUTHENTICATED'
        ELSE '❌ NOT AUTHENTICATED'
    END as status,
    COALESCE('User ID: ' || auth.uid()::text, 'No user session - policies will block access') as details;