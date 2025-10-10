-- Test Driver Online Status with Location Fix
-- Run this AFTER the driver goes online to verify the fix

SELECT 
  up.first_name,
  dp.is_online,
  dp.is_available,
  dp.current_latitude IS NOT NULL as has_latitude,
  dp.current_longitude IS NOT NULL as has_longitude,
  dp.location_updated_at,
  CASE 
    WHEN dp.is_online = true 
         AND dp.is_available = true 
         AND dp.is_verified = true 
         AND dp.current_latitude IS NOT NULL 
         AND dp.current_longitude IS NOT NULL 
    THEN '✅ READY FOR PAIRING'
    ELSE '❌ NOT READY - Check criteria above'
  END as pairing_status
FROM user_profiles up
JOIN driver_profiles dp ON up.id = dp.id
WHERE up.user_type = 'driver' 
  AND up.first_name = 'Derek';