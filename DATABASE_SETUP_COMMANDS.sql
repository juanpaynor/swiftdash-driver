-- ========================================
-- SwiftDash Driver App - Database Schema Updates
-- Run these commands in Supabase SQL Editor
-- ========================================

-- 1. UPDATE existing driver_earnings table with new columns
-- ========================================

ALTER TABLE driver_earnings 
ADD COLUMN IF NOT EXISTS payment_method VARCHAR(20) NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash', 'card'));

ALTER TABLE driver_earnings 
ADD COLUMN IF NOT EXISTS platform_commission NUMERIC(10,2) NOT NULL DEFAULT 0;

ALTER TABLE driver_earnings 
ADD COLUMN IF NOT EXISTS driver_net_earnings NUMERIC(10,2) NOT NULL DEFAULT 0;

ALTER TABLE driver_earnings 
ADD COLUMN IF NOT EXISTS is_remittance_required BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE driver_earnings 
ADD COLUMN IF NOT EXISTS remittance_deadline TIMESTAMP WITH TIME ZONE;

ALTER TABLE driver_earnings 
ADD COLUMN IF NOT EXISTS remittance_id UUID;

-- Create performance index for payment method queries
CREATE INDEX IF NOT EXISTS idx_driver_earnings_payment_method ON driver_earnings(driver_id, payment_method);

-- 2. CREATE new driver_cash_balances table
-- ========================================

CREATE TABLE IF NOT EXISTS driver_cash_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID REFERENCES driver_profiles(id) UNIQUE,
  current_balance NUMERIC(10,2) NOT NULL DEFAULT 0,
  pending_remittance NUMERIC(10,2) NOT NULL DEFAULT 0,
  last_remittance_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  next_remittance_due TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_driver_cash_balances_driver ON driver_cash_balances(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_cash_balances_due_date ON driver_cash_balances(next_remittance_due);

-- 3. CREATE new cash_remittances table
-- ========================================

CREATE TABLE IF NOT EXISTS cash_remittances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID REFERENCES driver_profiles(id),
  amount NUMERIC(10,2) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'overdue')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  processed_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  paymaya_transaction_id VARCHAR(100),
  failure_reason TEXT,
  earnings_ids UUID[] NOT NULL DEFAULT '{}'
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_cash_remittances_driver ON cash_remittances(driver_id);
CREATE INDEX IF NOT EXISTS idx_cash_remittances_status ON cash_remittances(status);
CREATE INDEX IF NOT EXISTS idx_cash_remittances_created ON cash_remittances(created_at);

-- 4. ADD foreign key constraint for remittance_id (after cash_remittances table exists)
-- ========================================

ALTER TABLE driver_earnings 
ADD CONSTRAINT IF NOT EXISTS fk_driver_earnings_remittance 
FOREIGN KEY (remittance_id) REFERENCES cash_remittances(id);

-- ========================================
-- VERIFICATION QUERIES (optional - run to verify)
-- ========================================

-- Check if all tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('driver_earnings', 'driver_cash_balances', 'cash_remittances');

-- Check driver_earnings columns
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns 
WHERE table_name = 'driver_earnings' 
AND table_schema = 'public'
ORDER BY ordinal_position;

-- Check indexes
SELECT indexname, tablename 
FROM pg_indexes 
WHERE tablename IN ('driver_earnings', 'driver_cash_balances', 'cash_remittances');