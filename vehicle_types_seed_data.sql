-- Insert default vehicle types for SwiftDash
-- Run this in your Supabase SQL editor if the vehicle_types table is empty

INSERT INTO vehicle_types (id, name, description, max_weight_kg, base_price, price_per_km, is_active, created_at, updated_at)
VALUES
  (
    'motorcycle-01', 
    'Motorcycle', 
    'Perfect for small packages and documents. Fast delivery in urban areas.', 
    5.0, 
    50.00, 
    8.50, 
    true, 
    NOW(), 
    NOW()
  ),
  (
    'sedan-01', 
    'Sedan Car', 
    'Standard car for medium-sized packages and multiple stops.', 
    20.0, 
    80.00, 
    12.00, 
    true, 
    NOW(), 
    NOW()
  ),
  (
    'suv-01', 
    'SUV', 
    'Spacious vehicle for larger packages and bulky items.', 
    50.0, 
    120.00, 
    15.00, 
    true, 
    NOW(), 
    NOW()
  ),
  (
    'pickup-01', 
    'Pickup Truck', 
    'Open bed truck for construction materials and large items.', 
    200.0, 
    150.00, 
    18.00, 
    true, 
    NOW(), 
    NOW()
  ),
  (
    'van-01', 
    'Cargo Van', 
    'Enclosed van perfect for furniture and appliance delivery.', 
    300.0, 
    200.00, 
    22.00, 
    true, 
    NOW(), 
    NOW()
  ),
  (
    'truck-01', 
    'Small Truck', 
    'For heavy cargo and commercial deliveries.', 
    1000.0, 
    300.00, 
    28.00, 
    true, 
    NOW(), 
    NOW()
  )
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  max_weight_kg = EXCLUDED.max_weight_kg,
  base_price = EXCLUDED.base_price,
  price_per_km = EXCLUDED.price_per_km,
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

-- Verify the data was inserted
SELECT 
  id,
  name,
  description,
  max_weight_kg,
  base_price,
  price_per_km,
  is_active
FROM vehicle_types 
WHERE is_active = true
ORDER BY max_weight_kg;