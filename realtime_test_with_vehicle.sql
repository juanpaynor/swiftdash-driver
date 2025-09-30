-- Realtime test using your created user and existing vehicle type
-- First create user_profile for the user if it doesn't exist
INSERT INTO user_profiles (
    id, 
    first_name, 
    last_name, 
    phone_number, 
    user_type, 
    status, 
    created_at, 
    updated_at
) VALUES (
    '8c2c06e0-2bd3-4a6a-b712-cf0d42576f38',
    'Test',
    'Customer',
    '+1234567890',
    'customer',
    'active',
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- Now create the delivery
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
  '8c2c06e0-2bd3-4a6a-b712-cf0d42576f38', -- Your user ID
  'fd74e9d1-2577-4103-a0e9-acea646cc210', -- Motorcycle ID from your output
  'pending',
  'REALTIME TEST - ' || NOW(),
  14.5358,
  120.9822,
  'Test Sender',
  '+1234567890',
  'REALTIME DELIVERY - ' || NOW(),
  14.5515,
  121.0511,
  'Test Receiver',
  '+0987654321',
  'Realtime Test Package',
  49.00,
  NOW(),
  NOW()
);

-- Verify it was created
SELECT 
  id, 
  status, 
  pickup_address, 
  delivery_address, 
  total_price,
  created_at
FROM deliveries 
WHERE pickup_address LIKE '%REALTIME TEST%'
ORDER BY created_at DESC;