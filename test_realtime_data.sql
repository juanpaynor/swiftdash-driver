-- ============================================
-- Test Data for Realtime Functionality
-- ============================================
-- Run this in Supabase SQL Editor to create test deliveries

-- First, let's see what drivers are available
SELECT id, first_name, last_name, phone_number 
FROM user_profiles 
WHERE user_type = 'driver';

-- Get vehicle types
SELECT id, name, base_price 
FROM vehicle_types 
WHERE is_active = true 
LIMIT 3;

-- Create a test customer (if you don't have one)
INSERT INTO user_profiles (id, first_name, last_name, phone_number, user_type, status, created_at, updated_at)
VALUES (
  gen_random_uuid(),
  'Test',
  'Customer', 
  '+1234567890',
  'customer',
  'active',
  NOW(),
  NOW()
)
ON CONFLICT (id) DO NOTHING;

-- Get the test customer ID
SELECT id FROM user_profiles WHERE user_type = 'customer' AND first_name = 'Test' LIMIT 1;

-- Create a test delivery (replace the UUIDs with actual IDs from above queries)
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
  (SELECT id FROM user_profiles WHERE user_type = 'customer' AND first_name = 'Test' LIMIT 1),
  (SELECT id FROM vehicle_types WHERE is_active = true LIMIT 1),
  'pending',
  'McDonald''s Ayala Avenue, Makati City',
  14.5547,
  121.0244,
  'Test Customer',
  '+1234567890',
  '123 Main Street, Bonifacio Global City',
  14.5515,
  121.0511,
  'John Doe',
  '+0987654321',
  'Food delivery - 2 burgers, 1 fries',
  250.00,
  NOW(),
  NOW()
);

-- Verify the test delivery was created
SELECT id, status, pickup_address, delivery_address, total_price, created_at
FROM deliveries 
WHERE pickup_address LIKE '%McDonald%'
ORDER BY created_at DESC;