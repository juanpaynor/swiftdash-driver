-- Debug: Check if our test delivery was actually created
SELECT 
  'Recent deliveries created:' as info,
  '' as id,
  '' as status,
  '' as pickup_address,
  '' as created_at;

SELECT 
  'data' as info,
  id, 
  status, 
  pickup_address,
  created_at::text
FROM deliveries 
ORDER BY created_at DESC 
LIMIT 5;

-- Check specifically for our realtime test
SELECT 
  'Realtime test deliveries:' as info,
  '' as id,
  '' as status,
  '' as pickup_address,
  '' as created_at;

SELECT 
  'data' as info,
  id, 
  status, 
  pickup_address,
  created_at::text
FROM deliveries 
WHERE pickup_address LIKE '%REALTIME%'
ORDER BY created_at DESC;