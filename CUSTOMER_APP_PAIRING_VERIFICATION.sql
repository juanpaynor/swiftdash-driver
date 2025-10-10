-- 🚨 CUSTOMER APP PAIRING VERIFICATION
-- Run this IMMEDIATELY after driver goes online to verify pairing will work

-- 1. ✅ CHECK: Drivers meeting ALL customer app criteria
SELECT 
  '🚨 CUSTOMER APP SEARCH QUERY SIMULATION' as test_name,
  up.first_name || ' ' || up.last_name as driver_name,
  dp.is_verified,
  dp.is_online,
  dp.is_available,  
  dp.current_latitude,
  dp.current_longitude,
  dp.location_updated_at,
  -- This exactly matches customer app search criteria
  CASE 
    WHEN dp.is_verified = true 
         AND dp.is_online = true 
         AND dp.is_available = true 
         AND dp.current_latitude IS NOT NULL 
         AND dp.current_longitude IS NOT NULL 
    THEN '✅ WILL BE FOUND BY CUSTOMER APP'
    ELSE '❌ CUSTOMER APP CANNOT FIND THIS DRIVER'
  END as customer_app_visibility
FROM user_profiles up
JOIN driver_profiles dp ON up.id = dp.id
WHERE up.user_type = 'driver'
ORDER BY dp.updated_at DESC;

-- 2. 🔍 DETAILED DIAGNOSIS: Why drivers might not be discoverable
SELECT 
  '🔍 DETAILED DIAGNOSIS' as test_name,
  up.first_name || ' ' || up.last_name as driver_name,
  CASE WHEN dp.is_verified = true THEN '✅' ELSE '❌ NOT VERIFIED' END as verified_status,
  CASE WHEN dp.is_online = true THEN '✅' ELSE '❌ NOT ONLINE' END as online_status,
  CASE WHEN dp.is_available = true THEN '✅' ELSE '❌ NOT AVAILABLE' END as available_status,
  CASE WHEN dp.current_latitude IS NOT NULL THEN '✅' ELSE '❌ NO LATITUDE' END as latitude_status,
  CASE WHEN dp.current_longitude IS NOT NULL THEN '✅' ELSE '❌ NO LONGITUDE' END as longitude_status,
  CASE WHEN dp.location_updated_at IS NOT NULL THEN '✅' ELSE '❌ NO LOCATION TIMESTAMP' END as timestamp_status
FROM user_profiles up
JOIN driver_profiles dp ON up.id = dp.id
WHERE up.user_type = 'driver'
ORDER BY dp.updated_at DESC;

-- 3. 📍 LOCATION FRESHNESS: Check if GPS data is recent
SELECT 
  '📍 LOCATION FRESHNESS CHECK' as test_name,
  up.first_name || ' ' || up.last_name as driver_name,
  dp.current_latitude,
  dp.current_longitude,
  dp.location_updated_at,
  EXTRACT(EPOCH FROM (NOW() - dp.location_updated_at))/60 as minutes_since_location_update,
  CASE 
    WHEN dp.location_updated_at IS NULL THEN '❌ NO LOCATION DATA'
    When EXTRACT(EPOCH FROM (NOW() - dp.location_updated_at))/60 < 5 THEN '✅ FRESH (< 5 min)'
    WHEN EXTRACT(EPOCH FROM (NOW() - dp.location_updated_at))/60 < 15 THEN '⚠️ OKAY (< 15 min)'
    ELSE '❌ STALE (> 15 min)'
  END as location_freshness
FROM user_profiles up
JOIN driver_profiles dp ON up.id = dp.id
WHERE up.user_type = 'driver' AND dp.is_online = true
ORDER BY dp.location_updated_at DESC;

-- 4. 🎯 FINAL VERIFICATION: Exactly what customer app will find
SELECT 
  '🎯 CUSTOMER APP FINAL RESULT' as test_name,
  COUNT(*) as drivers_customer_app_will_find,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ SUCCESS - Customer app will find drivers!'
    ELSE '❌ FAILURE - Customer app will find ZERO drivers'
  END as pairing_status
FROM driver_profiles dp
JOIN user_profiles up ON up.id = dp.id
WHERE up.user_type = 'driver'
  AND dp.is_verified = true 
  AND dp.is_online = true 
  AND dp.is_available = true 
  AND dp.current_latitude IS NOT NULL 
  AND dp.current_longitude IS NOT NULL;

-- 5. 🚨 EMERGENCY FIX: If still no drivers found, run this
-- UPDATE driver_profiles 
-- SET 
--   is_verified = true,
--   is_online = true,
--   is_available = true,
--   current_latitude = 14.5995,  -- Manila coordinates as fallback
--   current_longitude = 121.0244,
--   location_updated_at = NOW()
-- WHERE id IN (
--   SELECT dp.id FROM driver_profiles dp 
--   JOIN user_profiles up ON up.id = dp.id 
--   WHERE up.user_type = 'driver'
-- );