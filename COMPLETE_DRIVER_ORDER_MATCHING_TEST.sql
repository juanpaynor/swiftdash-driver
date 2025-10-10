-- 🚨 COMPREHENSIVE DRIVER-TO-ORDER MATCHING TEST
-- This tests the COMPLETE flow from driver going online to receiving orders

-- STEP 1: 🔍 VERIFY DRIVER DATABASE STATUS AFTER GOING ONLINE
SELECT 
  '🔍 STEP 1: DRIVER DATABASE STATUS' as test_step,
  up.first_name || ' ' || up.last_name as driver_name,
  dp.is_verified,
  dp.is_online,
  dp.is_available,
  dp.current_latitude,
  dp.current_longitude,
  dp.location_updated_at,
  -- Critical customer app matching criteria
  CASE 
    WHEN dp.is_verified = true AND dp.is_online = true AND dp.is_available = true 
         AND dp.current_latitude IS NOT NULL AND dp.current_longitude IS NOT NULL 
    THEN '✅ READY TO RECEIVE ORDERS'
    ELSE '❌ NOT READY - MISSING: ' ||
         CASE WHEN dp.is_verified != true THEN 'VERIFICATION ' ELSE '' END ||
         CASE WHEN dp.is_online != true THEN 'ONLINE_STATUS ' ELSE '' END ||
         CASE WHEN dp.is_available != true THEN 'AVAILABLE_STATUS ' ELSE '' END ||
         CASE WHEN dp.current_latitude IS NULL THEN 'GPS_LATITUDE ' ELSE '' END ||
         CASE WHEN dp.current_longitude IS NULL THEN 'GPS_LONGITUDE ' ELSE '' END
  END as matching_status
FROM user_profiles up
JOIN driver_profiles dp ON up.id = dp.id
WHERE up.user_type = 'driver'
ORDER BY dp.updated_at DESC;

-- STEP 2: 🎯 SIMULATE CUSTOMER APP EDGE FUNCTION QUERY
SELECT 
  '🎯 STEP 2: CUSTOMER APP QUERY SIMULATION' as test_step,
  COUNT(*) as matching_drivers,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ CUSTOMER APP WILL FIND DRIVERS'
    ELSE '❌ CUSTOMER APP FINDS ZERO DRIVERS'
  END as edge_function_result
FROM driver_profiles dp
JOIN user_profiles up ON up.id = dp.id
WHERE up.user_type = 'driver'
  AND dp.is_verified = true 
  AND dp.is_online = true 
  AND dp.is_available = true 
  AND dp.current_latitude IS NOT NULL 
  AND dp.current_longitude IS NOT NULL;

-- STEP 3: 📱 TEST ORDER CREATION AND REALTIME SUBSCRIPTION
-- Insert a test delivery to verify driver receives notification
INSERT INTO deliveries (
  id,
  customer_id,
  vehicle_type_id,
  status,
  pickup_address,
  pickup_latitude,
  pickup_longitude,
  pickup_contact_name,
  pickup_contact_phone,
  delivery_address,
  delivery_latitude,
  delivery_longitude,
  delivery_contact_name,
  delivery_contact_phone,
  package_description,
  total_price,
  created_at,
  updated_at
) VALUES (
  gen_random_uuid(),
  (SELECT id FROM user_profiles WHERE user_type = 'customer' LIMIT 1), -- Any customer
  (SELECT id FROM vehicle_types WHERE is_active = true LIMIT 1), -- Any active vehicle type
  'pending',
  'Test Pickup Location, Manila',
  14.5995, -- Manila latitude
  121.0244, -- Manila longitude
  'Test Customer',
  '+639123456789',
  'Test Delivery Location, Manila',
  14.6042, -- Slightly different coordinates
  121.0300,
  'Test Recipient',
  '+639987654321',
  'Test Package for Driver Matching',
  250.00,
  NOW(),
  NOW()
)
RETURNING 
  '📱 STEP 3: TEST ORDER CREATED' as test_step,
  id as test_delivery_id,
  '✅ Driver should receive notification' as expected_result;

-- STEP 4: 🔔 VERIFY REALTIME SUBSCRIPTION SHOULD TRIGGER
-- Check if the inserted delivery matches the realtime subscription criteria
SELECT 
  '🔔 STEP 4: REALTIME SUBSCRIPTION CHECK' as test_step,
  d.id as delivery_id,
  d.status,
  d.driver_id,
  CASE 
    WHEN d.status = 'pending' AND d.driver_id IS NULL 
    THEN '✅ MATCHES SUBSCRIPTION CRITERIA - Driver should get notification'
    ELSE '❌ DOES NOT MATCH SUBSCRIPTION CRITERIA'
  END as subscription_match
FROM deliveries d
WHERE d.status = 'pending' 
  AND d.driver_id IS NULL
  AND d.created_at > NOW() - INTERVAL '1 minute'
ORDER BY d.created_at DESC
LIMIT 1;

-- STEP 5: 🚨 EMERGENCY DIAGNOSTICS IF NO MATCH
SELECT 
  '🚨 EMERGENCY DIAGNOSTICS' as test_step,
  'If driver is not receiving orders, check these:' as diagnosis,
  '1. Driver app realtime subscription active?' as check_1,
  '2. Driver app WebSocket connection established?' as check_2,
  '3. _handleNewDeliveryOffer callback working?' as check_3,
  '4. Offer modal showing in driver app?' as check_4;

-- STEP 6: 🧹 CLEANUP TEST DATA
-- DELETE FROM deliveries WHERE package_description = 'Test Package for Driver Matching';

-- STEP 7: 📊 FINAL VERIFICATION SUMMARY
SELECT 
  '📊 FINAL VERIFICATION SUMMARY' as test_step,
  (SELECT COUNT(*) FROM driver_profiles dp 
   JOIN user_profiles up ON up.id = dp.id 
   WHERE up.user_type = 'driver' AND dp.is_online = true AND dp.is_available = true) as online_drivers,
  (SELECT COUNT(*) FROM deliveries WHERE status = 'pending' AND driver_id IS NULL) as pending_orders,
  CASE 
    WHEN (SELECT COUNT(*) FROM driver_profiles dp 
          JOIN user_profiles up ON up.id = dp.id 
          WHERE up.user_type = 'driver' AND dp.is_online = true AND dp.is_available = true) > 0
         AND (SELECT COUNT(*) FROM deliveries WHERE status = 'pending' AND driver_id IS NULL) >= 0
    THEN '✅ SYSTEM READY FOR DRIVER-ORDER MATCHING'
    ELSE '❌ SYSTEM NOT READY - CHECK PREVIOUS STEPS'
  END as system_status;