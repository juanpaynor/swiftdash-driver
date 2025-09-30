-- Check current users and constraints
SELECT 'Current auth users:' as info;
SELECT id, email, created_at FROM auth.users LIMIT 5;

SELECT 'Current user_profiles:' as info;
SELECT id, first_name, last_name, user_type FROM user_profiles LIMIT 5;

-- Check constraints on deliveries table
SELECT 'Deliveries table constraints:' as info;
SELECT 
    conname as constraint_name,
    contype as constraint_type,
    confrelid::regclass as foreign_table
FROM pg_constraint 
WHERE conrelid = 'deliveries'::regclass;

-- Simple option: Use any existing auth user ID if available
DO $$
DECLARE
    existing_user_id uuid;
    test_vehicle_type_id uuid := 'fd74e9d1-2577-4103-a0e9-acea646cc210';
BEGIN
    -- Try to get any existing user from auth.users
    SELECT id INTO existing_user_id FROM auth.users LIMIT 1;
    
    IF existing_user_id IS NOT NULL THEN
        -- Create user_profile if it doesn't exist
        INSERT INTO user_profiles (
            id, first_name, last_name, phone_number, user_type, status, created_at, updated_at
        ) VALUES (
            existing_user_id, 'Test', 'Customer', '+1234567890', 'customer', 'active', NOW(), NOW()
        ) ON CONFLICT (id) DO NOTHING;
        
        -- Create the test delivery
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
          existing_user_id,
          test_vehicle_type_id,
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
        
        RAISE NOTICE 'SUCCESS: Created test delivery with customer_id: %', existing_user_id;
    ELSE
        RAISE NOTICE 'No users found in auth.users - you need to create a user first';
    END IF;
END
$$;

-- Check what was created
SELECT 
  id, 
  customer_id,
  status, 
  pickup_address, 
  delivery_address, 
  total_price,
  created_at
FROM deliveries 
WHERE pickup_address LIKE '%REALTIME TEST%'
ORDER BY created_at DESC;