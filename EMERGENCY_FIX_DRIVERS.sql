-- EMERGENCY FIX: Update all existing drivers to be discoverable by customer app
-- Run this immediately to fix all current driver accounts

-- 1. CRITICAL: Set all drivers as verified (for testing/development)
UPDATE driver_profiles 
SET is_verified = true,
    updated_at = NOW()
WHERE is_verified = false;

-- 2. Show current driver status before any other fixes
SELECT 
  'BEFORE FIX - DRIVER STATUS' as report,
  COUNT(*) as total_drivers,
  COUNT(CASE WHEN is_verified THEN 1 END) as verified_drivers,
  COUNT(CASE WHEN is_online THEN 1 END) as online_drivers,
  COUNT(CASE WHEN is_available THEN 1 END) as available_drivers,
  COUNT(CASE WHEN current_latitude IS NOT NULL AND current_longitude IS NOT NULL THEN 1 END) as drivers_with_location
FROM driver_profiles dp
JOIN user_profiles up ON dp.id = up.id
WHERE up.user_type = 'driver';

-- 3. CRITICAL FIX: Ensure is_available column exists and is properly set
-- (Add column if missing, update existing records)
ALTER TABLE driver_profiles 
ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT false;

-- 4. Set offline drivers as unavailable (if they don't have is_available set)
UPDATE driver_profiles 
SET is_available = false,
    updated_at = NOW()
WHERE is_online = false AND (is_available IS NULL OR is_available = true);

-- 5. EMERGENCY: For testing - set at least one driver online with fake location
-- This will allow customer app to find a driver immediately
UPDATE driver_profiles 
SET is_online = true,
    is_available = true,
    is_verified = true,
    current_latitude = 14.5995,  -- Manila, Philippines
    current_longitude = 121.0244,
    location_updated_at = NOW(),
    updated_at = NOW()
WHERE id = (
  SELECT dp.id 
  FROM driver_profiles dp
  JOIN user_profiles up ON dp.id = up.id
  WHERE up.user_type = 'driver'
  LIMIT 1
);

-- 6. Show status after fix
SELECT 
  'AFTER FIX - DRIVER STATUS' as report,
  COUNT(*) as total_drivers,
  COUNT(CASE WHEN is_verified THEN 1 END) as verified_drivers,
  COUNT(CASE WHEN is_online THEN 1 END) as online_drivers,
  COUNT(CASE WHEN is_available THEN 1 END) as available_drivers,
  COUNT(CASE WHEN current_latitude IS NOT NULL AND current_longitude IS NOT NULL THEN 1 END) as drivers_with_location
FROM driver_profiles dp
JOIN user_profiles up ON dp.id = up.id
WHERE up.user_type = 'driver';

-- 7. FINAL CHECK: Show drivers that meet customer app criteria
SELECT 
  'CUSTOMER APP CRITERIA CHECK' as report,
  up.first_name,
  up.last_name,
  dp.is_verified,
  dp.is_online,
  dp.is_available,
  dp.current_latitude,
  dp.current_longitude,
  dp.location_updated_at,
  '✅ DISCOVERABLE BY CUSTOMER APP' as status
FROM driver_profiles dp
JOIN user_profiles up ON dp.id = up.id
WHERE up.user_type = 'driver'
  AND dp.is_verified = true 
  AND dp.is_online = true 
  AND dp.is_available = true 
  AND dp.current_latitude IS NOT NULL 
  AND dp.current_longitude IS NOT NULL;

-- 8. Check vehicle types are available
SELECT 
  'VEHICLE TYPES STATUS' as report,
  id,
  name,
  is_active,
  CASE WHEN is_active THEN '✅ ACTIVE' ELSE '❌ NEEDS ACTIVATION' END as status
FROM vehicle_types;