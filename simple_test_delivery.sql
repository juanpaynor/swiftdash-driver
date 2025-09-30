-- Simple test delivery (using existing data or minimal approach)

-- Option 1: Check what users and vehicle types we have available
SELECT 'Available customers:' as info;
SELECT id, first_name, last_name, user_type FROM user_profiles WHERE user_type = 'customer' LIMIT 3;

SELECT 'Available vehicle types:' as info;
SELECT id, name, base_price FROM vehicle_types WHERE is_active = true LIMIT 3;

-- Option 2: Create delivery using existing data or with minimal foreign key dependencies
DO $$
DECLARE
    test_customer_id uuid;
    test_vehicle_type_id uuid;
BEGIN
    -- Try to get an existing customer
    SELECT id INTO test_customer_id FROM user_profiles WHERE user_type = 'customer' LIMIT 1;
    
    -- Get a vehicle type
    SELECT id INTO test_vehicle_type_id FROM vehicle_types WHERE is_active = true LIMIT 1;
    
    -- If we have both required IDs, create the delivery
    IF test_customer_id IS NOT NULL AND test_vehicle_type_id IS NOT NULL THEN
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
          test_customer_id,
          test_vehicle_type_id,
          'pending',
          'SM Mall of Asia, Pasay City',
          14.5358,
          120.9822,
          'Test Sender',
          '+1234567890',
          'BGC The Fort, Taguig City',
          14.5515,
          121.0511,
          'Test Receiver',
          '+0987654321',
          'Test package delivery',
          150.00,
          NOW(),
          NOW()
        );
        
        RAISE NOTICE 'Created test delivery with customer_id: % and vehicle_type_id: %', test_customer_id, test_vehicle_type_id;
    ELSE
        RAISE NOTICE 'Cannot create delivery - missing customer_id: % or vehicle_type_id: %', test_customer_id, test_vehicle_type_id;
        RAISE NOTICE 'You need to create these records first or modify the delivery table constraints';
    END IF;
END
$$;

-- Check if it was created
SELECT id, status, pickup_address, delivery_address, total_price 
FROM deliveries 
WHERE pickup_address LIKE '%SM Mall%';