-- Step 1: Create a test user in auth.users first
-- You need to run this in Supabase SQL Editor with admin privileges

-- Create a test user in auth.users table
INSERT INTO auth.users (
  id,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  role
) VALUES (
  gen_random_uuid(),
  'testcustomer@example.com',
  crypt('password123', gen_salt('bf')),
  NOW(),
  NOW(),
  NOW(),
  '{"provider": "email", "providers": ["email"]}',
  '{"first_name": "Test", "last_name": "Customer"}',
  false,
  'authenticated'
) ON CONFLICT (email) DO NOTHING
RETURNING id, email;

-- Get the created user ID
SELECT id, email FROM auth.users WHERE email = 'testcustomer@example.com';