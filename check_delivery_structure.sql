-- Check the exact structure of our test delivery
SELECT 
  id,
  customer_id,
  driver_id,
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
FROM deliveries 
WHERE pickup_address LIKE '%REALTIME TEST%'
ORDER BY created_at DESC
LIMIT 1;