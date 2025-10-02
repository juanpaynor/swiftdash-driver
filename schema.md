"addresses" table schema

create table public.addresses (
  id uuid not null default gen_random_uuid (),
  user_id uuid null,
  address_type text null default 'other'::text,
  street_address text not null,
  city text not null,
  postal_code text null,
  latitude numeric(10, 8) null,
  longitude numeric(11, 8) null,
  is_default boolean null default false,
  created_at timestamp with time zone null default now(),
  constraint addresses_pkey primary key (id),
  constraint addresses_user_id_fkey foreign KEY (user_id) references auth.users (id) on delete CASCADE,
  constraint addresses_address_type_check check (
    (
      address_type = any (array['home'::text, 'work'::text, 'other'::text])
    )
  )
) TABLESPACE pg_default;





"deliveries" table schema


create table public.deliveries (
  id uuid not null default gen_random_uuid (),
  customer_id uuid not null,
  driver_id uuid null,
  vehicle_type_id uuid not null,
  pickup_address text not null,
  pickup_latitude numeric(10, 8) not null,
  pickup_longitude numeric(11, 8) not null,
  pickup_contact_name text not null,
  pickup_contact_phone text not null,
  pickup_instructions text null,
  delivery_address text not null,
  delivery_latitude numeric(10, 8) not null,
  delivery_longitude numeric(11, 8) not null,
  delivery_contact_name text not null,
  delivery_contact_phone text not null,
  delivery_instructions text null,
  package_description text not null,
  package_weight numeric(8, 2) null,
  package_value numeric(10, 2) null,
  distance_km numeric(8, 2) null,
  estimated_duration integer null,
  total_price numeric(10, 2) not null,
  status text null default 'pending'::text,
  customer_rating integer null,
  driver_rating integer null,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  completed_at timestamp with time zone null,
  constraint deliveries_pkey primary key (id),
  constraint deliveries_customer_id_fkey foreign KEY (customer_id) references auth.users (id),
  constraint deliveries_driver_id_fkey foreign KEY (driver_id) references driver_profiles (id),
  constraint deliveries_customer_rating_check check (
    (
      (customer_rating >= 1)
      and (customer_rating <= 5)
    )
  ),
  constraint deliveries_driver_rating_check check (
    (
      (driver_rating >= 1)
      and (driver_rating <= 5)
    )
  ),
  constraint deliveries_status_check check (
    (
      status = any (
        array[
          'pending'::text,
          'driver_assigned'::text,
          'pickup_arrived'::text,
          'package_collected'::text,
          'in_transit'::text,
          'delivered'::text,
          'cancelled'::text,
          'failed'::text
        ]
      )
    )
  )
) TABLESPACE pg_default;



"delivery_tracking" table schema

create table public.delivery_tracking (
  id uuid not null default gen_random_uuid (),
  delivery_id uuid null,
  driver_id uuid null,
  latitude numeric(10, 8) not null,
  longitude numeric(11, 8) not null,
  status text null,
  created_at timestamp with time zone null default now(),
  constraint delivery_tracking_pkey primary key (id),
  constraint delivery_tracking_delivery_id_fkey foreign KEY (delivery_id) references deliveries (id) on delete CASCADE,
  constraint delivery_tracking_driver_id_fkey foreign KEY (driver_id) references driver_profiles (id)
) TABLESPACE pg_default;


"driver_profiles" table schema

create table public.driver_profiles (
  id uuid not null,
  vehicle_type_id uuid null,
  license_number text null,
  vehicle_model text null,
  is_verified boolean null default false,
  is_online boolean null default false,
  current_latitude numeric(10, 8) null,
  current_longitude numeric(11, 8) null,
  rating numeric(3, 2) null default 0.00,
  total_deliveries integer null default 0,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  is_available boolean null default false,
  location_updated_at timestamp with time zone null default now(),
  constraint driver_profiles_pkey primary key (id),
  constraint driver_profiles_id_fkey foreign KEY (id) references auth.users (id),
  constraint driver_profiles_vehicle_type_id_fkey foreign KEY (vehicle_type_id) references vehicle_types (id)
) TABLESPACE pg_default;


"user_profile" table schema

create table public.user_profiles (
  id uuid not null,
  phone_number character varying(20) not null,
  first_name character varying(100) not null,
  last_name character varying(100) not null,
  user_type text not null,
  profile_image_url text null,
  status text null default 'active'::text,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint user_profiles_pkey primary key (id),
  constraint user_profiles_phone_number_key unique (phone_number),
  constraint user_profiles_id_fkey foreign KEY (id) references auth.users (id),
  constraint user_profiles_status_check check (
    (
      status = any (
        array[
          'active'::text,
          'inactive'::text,
          'suspended'::text
        ]
      )
    )
  ),
  constraint user_profiles_user_type_check check (
    (
      user_type = any (
        array['customer'::text, 'driver'::text, 'admin'::text]
      )
    )
  )
) TABLESPACE pg_default;





"vehicle_types" table schema


create table public.vehicle_types (
  id uuid not null default gen_random_uuid (),
  name text not null,
  description text null,
  max_weight_kg numeric(8, 2) not null,
  base_price numeric(8, 2) not null,
  price_per_km numeric(6, 2) not null,
  icon_url text null,
  is_active boolean null default true,
  constraint vehicle_types_pkey primary key (id)
) TABLESPACE pg_default;