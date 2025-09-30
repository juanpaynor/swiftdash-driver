-- ============================================
-- ENABLE RLS ON MISSING TABLES
-- ============================================

-- Enable RLS on driver_profiles
ALTER TABLE driver_profiles ENABLE ROW LEVEL SECURITY;

-- Enable RLS on user_profiles  
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Verify RLS is now enabled
SELECT 
    tablename,
    CASE 
        WHEN rowsecurity THEN 'RLS ENABLED ✅'
        ELSE 'RLS DISABLED ❌'
    END as rls_status
FROM pg_tables 
WHERE schemaname = 'public'
AND tablename IN ('deliveries', 'driver_profiles', 'user_profiles', 'vehicle_types')
ORDER BY tablename;