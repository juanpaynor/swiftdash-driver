-- ============================================
-- SIMPLE DIAGNOSTIC SCRIPT
-- ============================================
-- Check basic database status

-- 1. Check if tables exist
SELECT 'Tables Check:' as info;
SELECT 
    table_name,
    'EXISTS' as status
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
ORDER BY table_name;

-- 2. Check realtime publication
SELECT 'Realtime Check:' as info;
SELECT 
    tablename,
    'REALTIME ENABLED' as status
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
ORDER BY tablename;

-- 3. Check RLS status
SELECT 'RLS Check:' as info;
SELECT 
    tablename,
    CASE WHEN rowsecurity THEN 'RLS ENABLED' ELSE 'RLS DISABLED' END as status
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY tablename;

-- 4. Check if we have any policies
SELECT 'Policies Check:' as info;
SELECT 
    tablename,
    COUNT(*) as policy_count
FROM pg_policies 
GROUP BY tablename
ORDER BY tablename;