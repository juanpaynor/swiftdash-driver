-- Quick realtime test without foreign key constraints
-- This creates a delivery with minimal dependencies for testing realtime

-- Option 1: Create delivery with NULL customer_id and vehicle_type_id (if allowed)
INSERT INTO deliveries (
  id,
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
  'pending',
  'Realtime Test Pickup - ' || NOW(),
  14.5358,
  120.9822,
  'Test Sender',
  '+1234567890',
  'Realtime Test Delivery - ' || NOW(),
  14.5515,
  121.0511,
  'Test Receiver',
  '+0987654321',
  'Realtime Test Package',
  99.00,
  NOW(),
  NOW()
);

-- Check what was created
SELECT 
  id, 
  status, 
  pickup_address, 
  delivery_address, 
  total_price,
  created_at
FROM deliveries 
WHERE pickup_address LIKE '%Realtime Test%'
ORDER BY created_at DESC
LIMIT 3;