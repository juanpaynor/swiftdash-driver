-- URGENT DEBUG: Driver Status Query for Customer App Pairing Issue
-- Run this in Supabase SQL Editor to check driver availability

-- 1. Check all drivers and their current status (FIXED SCHEMA)
SELECT 
  'ALL DRIVERS STATUS' as report_section,
  up.first_name,
  up.last_name,
  dp.is_online,
  dp.is_available,
  dp.is_verified,
  dp.current_latitude,
  dp.current_longitude,
  dp.location_updated_at,
  dp.updated_at as profile_updated_at
FROM user_profiles up
JOIN driver_profiles dp ON up.id = dp.id
WHERE up.user_type = 'driver'
ORDER BY dp.updated_at DESC;

-- 2. Check if driver meets ALL criteria for pairing
SELECT 
  up.first_name,
  up.last_name,
  dp.is_online,
  dp.is_available, 
  dp.is_verified,
  (dp.current_latitude IS NOT NULL) as has_latitude,
  (dp.current_longitude IS NOT NULL) as has_longitude,
  dp.location_updated_at,
  -- Check if driver meets ALL pairing criteria
  CASE 
    WHEN dp.is_online = true 
         AND dp.is_available = true 
         AND dp.is_verified = true 
         AND dp.current_latitude IS NOT NULL 
         AND dp.current_longitude IS NOT NULL 
    THEN '✅ AVAILABLE FOR PAIRING'
    ELSE '❌ NOT AVAILABLE - Check criteria above'
  END as pairing_status
FROM user_profiles up
JOIN driver_profiles dp ON up.id = dp.id
WHERE up.user_type = 'driver'
ORDER BY dp.updated_at DESC;

-- 3. Recent location updates (should be within last 10 minutes for active drivers)
SELECT 
  up.first_name,
  dp.current_latitude,
  dp.current_longitude,
  dp.location_updated_at,
  EXTRACT(EPOCH FROM (NOW() - dp.location_updated_at))/60 as minutes_since_last_update
FROM user_profiles up
JOIN driver_profiles dp ON up.id = dp.id
WHERE up.user_type = 'driver' 
  AND dp.is_online = true
ORDER BY dp.location_updated_at DESC;