-- 🚀 SwiftDash Optimized Realtime Database Migration

-- ===============================================
-- 1. DRIVER LOCATION HISTORY (For Critical Events Only)
-- ===============================================

-- Create driver_location_history table for storing only important location events
CREATE TABLE IF NOT EXISTS driver_location_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES driver_profiles(id) ON DELETE CASCADE,
  delivery_id UUID REFERENCES deliveries(id) ON DELETE CASCADE,
  latitude DECIMAL(10, 8) NOT NULL,
  longitude DECIMAL(11, 8) NOT NULL,
  event_type TEXT NOT NULL, -- 'pickup', 'delivery', 'break_start', 'break_end', 'shift_start', 'shift_end'
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  accuracy DECIMAL(5, 2),
  speed_kmh DECIMAL(5, 2),
  heading DECIMAL(5, 2),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_location_history_driver_time 
  ON driver_location_history(driver_id, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_location_history_delivery 
  ON driver_location_history(delivery_id);

CREATE INDEX IF NOT EXISTS idx_location_history_event_type 
  ON driver_location_history(event_type);

-- ===============================================
-- 2. DRIVER CURRENT STATUS (Lightweight Real-time Status)
-- ===============================================

-- Create driver_current_status table for lightweight real-time tracking
CREATE TABLE IF NOT EXISTS driver_current_status (
  driver_id UUID PRIMARY KEY REFERENCES driver_profiles(id) ON DELETE CASCADE,
  current_latitude DECIMAL(10, 8),
  current_longitude DECIMAL(11, 8),
  status TEXT NOT NULL DEFAULT 'offline', -- 'available', 'delivering', 'break', 'offline'
  speed_kmh DECIMAL(5, 2) DEFAULT 0,
  heading DECIMAL(5, 2),
  last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  current_delivery_id UUID REFERENCES deliveries(id) ON DELETE SET NULL,
  battery_level INTEGER, -- 0-100
  app_version TEXT,
  device_info TEXT
);

-- Index for status queries
CREATE INDEX IF NOT EXISTS idx_driver_status_status 
  ON driver_current_status(status);

CREATE INDEX IF NOT EXISTS idx_driver_status_delivery 
  ON driver_current_status(current_delivery_id);

-- ===============================================
-- 3. ENHANCED DRIVER PROFILES (Add New Fields)
-- ===============================================

-- Add new fields to driver_profiles if they don't exist
ALTER TABLE driver_profiles 
ADD COLUMN IF NOT EXISTS ltfrb_picture_url TEXT;

-- Add profile picture URL if not exists (should already exist)
ALTER TABLE driver_profiles 
ADD COLUMN IF NOT EXISTS profile_picture_url TEXT;

-- Add vehicle picture URL if not exists (should already exist)  
ALTER TABLE driver_profiles 
ADD COLUMN IF NOT EXISTS vehicle_picture_url TEXT;

-- ===============================================
-- 4. ANALYTICS EVENTS (For Batched Analytics)
-- ===============================================

-- Create analytics_events table for batched processing
CREATE TABLE IF NOT EXISTS analytics_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  driver_id UUID REFERENCES driver_profiles(id) ON DELETE CASCADE,
  delivery_id UUID REFERENCES deliveries(id) ON DELETE CASCADE,
  event_data JSONB NOT NULL,
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  processed_at TIMESTAMP WITH TIME ZONE,
  batch_id UUID
);

-- Indexes for analytics
CREATE INDEX IF NOT EXISTS idx_analytics_events_type_time 
  ON analytics_events(event_type, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_analytics_events_driver 
  ON analytics_events(driver_id);

CREATE INDEX IF NOT EXISTS idx_analytics_events_delivery 
  ON analytics_events(delivery_id);

CREATE INDEX IF NOT EXISTS idx_analytics_events_processed 
  ON analytics_events(processed_at) WHERE processed_at IS NULL;

-- ===============================================
-- 5. ROW-LEVEL SECURITY (RLS) POLICIES
-- ===============================================

-- Enable RLS on new tables
ALTER TABLE driver_location_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_current_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Drivers can only access their own location history
DROP POLICY IF EXISTS "drivers_own_location_history" ON driver_location_history;
CREATE POLICY "drivers_own_location_history" ON driver_location_history
  FOR ALL TO authenticated
  USING (driver_id = auth.uid());

-- RLS Policy: Customers can see driver location history for their deliveries
DROP POLICY IF EXISTS "customers_see_delivery_location_history" ON driver_location_history;
CREATE POLICY "customers_see_delivery_location_history" ON driver_location_history
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM deliveries
      WHERE deliveries.id = driver_location_history.delivery_id
      AND deliveries.customer_id = auth.uid()
    )
  );

-- RLS Policy: Drivers can only access their own current status
DROP POLICY IF EXISTS "drivers_own_current_status" ON driver_current_status;
CREATE POLICY "drivers_own_current_status" ON driver_current_status
  FOR ALL TO authenticated
  USING (driver_id = auth.uid());

-- RLS Policy: Customers can see current status of drivers assigned to their deliveries
DROP POLICY IF EXISTS "customers_see_assigned_driver_status" ON driver_current_status;
CREATE POLICY "customers_see_assigned_driver_status" ON driver_current_status
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM deliveries
      WHERE deliveries.driver_id = driver_current_status.driver_id
      AND deliveries.customer_id = auth.uid()
      AND deliveries.status IN ('driver_assigned', 'package_collected', 'in_transit')
    )
  );

-- RLS Policy: Analytics events - drivers can only see their own
DROP POLICY IF EXISTS "drivers_own_analytics" ON analytics_events;
CREATE POLICY "drivers_own_analytics" ON analytics_events
  FOR ALL TO authenticated
  USING (driver_id = auth.uid());

-- ===============================================
-- 6. ENHANCED DELIVERIES TABLE POLICIES
-- ===============================================

-- Update existing deliveries RLS policies to be more granular

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "customers_own_deliveries" ON deliveries;
DROP POLICY IF EXISTS "drivers_assigned_deliveries" ON deliveries;

-- Customers can only see their own deliveries
CREATE POLICY "customers_own_deliveries" ON deliveries
  FOR ALL TO authenticated
  USING (customer_id = auth.uid());

-- Drivers can see deliveries assigned to them OR pending deliveries (for offers)
CREATE POLICY "drivers_assigned_and_pending_deliveries" ON deliveries
  FOR SELECT TO authenticated
  USING (
    driver_id = auth.uid() 
    OR (status = 'pending' AND driver_id IS NULL)
  );

-- Drivers can update deliveries assigned to them
CREATE POLICY "drivers_update_assigned_deliveries" ON deliveries
  FOR UPDATE TO authenticated
  USING (driver_id = auth.uid());

-- ===============================================
-- 7. DRIVER PROFILES ENHANCED RLS
-- ===============================================

-- Update driver profiles RLS for granular access

-- Drop existing policies
DROP POLICY IF EXISTS "customers_see_assigned_drivers" ON driver_profiles;
DROP POLICY IF EXISTS "drivers_own_profile" ON driver_profiles;

-- Drivers can see and update their own profile
CREATE POLICY "drivers_own_profile" ON driver_profiles
  FOR ALL TO authenticated
  USING (id = auth.uid());

-- Customers can see limited driver info for their active deliveries
CREATE POLICY "customers_see_assigned_drivers_limited" ON driver_profiles
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM deliveries
      WHERE deliveries.driver_id = driver_profiles.id
      AND deliveries.customer_id = auth.uid()
      AND deliveries.status IN ('driver_assigned', 'package_collected', 'in_transit')
    )
  );

-- Admins can see drivers in their assigned region
CREATE POLICY "admins_regional_drivers" ON driver_profiles
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_profiles.id = auth.uid()
      AND user_profiles.user_type = 'admin'
      -- Add region-based filtering here when regions are implemented
    )
  );

-- ===============================================
-- 8. FUNCTIONS FOR AUTOMATED CLEANUP
-- ===============================================

-- Function to clean up old location history (keep only last 30 days)
CREATE OR REPLACE FUNCTION cleanup_old_location_history()
RETURNS void AS $$
BEGIN
  DELETE FROM driver_location_history
  WHERE timestamp < NOW() - INTERVAL '30 days';
  
  RAISE NOTICE 'Cleaned up old location history records';
END;
$$ LANGUAGE plpgsql;

-- Function to clean up processed analytics events (keep only last 7 days)
CREATE OR REPLACE FUNCTION cleanup_processed_analytics()
RETURNS void AS $$
BEGIN
  DELETE FROM analytics_events
  WHERE processed_at IS NOT NULL
  AND processed_at < NOW() - INTERVAL '7 days';
  
  RAISE NOTICE 'Cleaned up processed analytics events';
END;
$$ LANGUAGE plpgsql;

-- ===============================================
-- 9. AUTOMATED CLEANUP SCHEDULE (Optional)
-- ===============================================

-- Note: These would typically be run via cron jobs or scheduled functions
-- Example cron schedule (uncomment if using pg_cron extension):

-- SELECT cron.schedule('cleanup-location-history', '0 2 * * *', 'SELECT cleanup_old_location_history();');
-- SELECT cron.schedule('cleanup-analytics', '0 3 * * *', 'SELECT cleanup_processed_analytics();');

-- ===============================================
-- 10. PERFORMANCE OPTIMIZATIONS
-- ===============================================

-- Create partial indexes for better performance
CREATE INDEX IF NOT EXISTS idx_deliveries_pending_unassigned 
  ON deliveries(created_at DESC) 
  WHERE status = 'pending' AND driver_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_deliveries_active_by_driver 
  ON deliveries(driver_id, status, created_at DESC) 
  WHERE status IN ('driver_assigned', 'package_collected', 'in_transit');

-- Create composite index for location queries
CREATE INDEX IF NOT EXISTS idx_driver_status_location 
  ON driver_current_status(status, current_latitude, current_longitude) 
  WHERE status = 'available';

-- ===============================================
-- 11. TRIGGERS FOR AUTOMATIC STATUS UPDATES
-- ===============================================

-- Function to update driver current status when delivery status changes
CREATE OR REPLACE FUNCTION update_driver_status_on_delivery_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Update driver current status based on delivery status
  IF NEW.status = 'driver_assigned' AND OLD.status = 'pending' THEN
    UPDATE driver_current_status 
    SET status = 'delivering', current_delivery_id = NEW.id, last_updated = NOW()
    WHERE driver_id = NEW.driver_id;
  ELSIF NEW.status = 'delivered' OR NEW.status = 'cancelled' THEN
    UPDATE driver_current_status 
    SET status = 'available', current_delivery_id = NULL, last_updated = NOW()
    WHERE driver_id = NEW.driver_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for automatic status updates
DROP TRIGGER IF EXISTS trigger_update_driver_status ON deliveries;
CREATE TRIGGER trigger_update_driver_status
  AFTER UPDATE ON deliveries
  FOR EACH ROW
  EXECUTE FUNCTION update_driver_status_on_delivery_change();

-- ===============================================
-- 12. INITIAL DATA SETUP
-- ===============================================

-- Initialize driver_current_status for existing drivers
INSERT INTO driver_current_status (driver_id, status, last_updated)
SELECT id, 'offline', NOW()
FROM driver_profiles
WHERE id NOT IN (SELECT driver_id FROM driver_current_status)
ON CONFLICT (driver_id) DO NOTHING;

-- ===============================================
-- 13. GRANTS AND PERMISSIONS
-- ===============================================

-- Grant necessary permissions to authenticated users
GRANT SELECT, INSERT, UPDATE, DELETE ON driver_location_history TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON driver_current_status TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics_events TO authenticated;

-- Grant usage on sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- ===============================================
-- MIGRATION COMPLETE
-- ===============================================

-- Add comment to track migration
COMMENT ON TABLE driver_location_history IS 'Optimized location storage for critical events only - SwiftDash v2.0';
COMMENT ON TABLE driver_current_status IS 'Lightweight real-time driver status - SwiftDash v2.0';
COMMENT ON TABLE analytics_events IS 'Batched analytics events - SwiftDash v2.0';

SELECT 'SwiftDash Optimized Realtime Database Migration Complete!' as status;