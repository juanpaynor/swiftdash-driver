# 💳 SwiftDash Payment System Coordination - Driver App Updates

**Date:** October 7, 2025  
**From:** Driver App Development Team  
**To:** Customer App Development Team  
**Priority:** HIGH - Database Schema Changes Required

---

## 🎯 **COORDINATION REQUIRED - PAYMENT SYSTEM ENHANCEMENT**

We have implemented a comprehensive **Card vs Cash Payment System** in the Driver App that requires coordination with the Customer App for proper integration.

---

## ✅ **EXISTING DELIVERIES TABLE STRUCTURE CONFIRMED**

The `deliveries` table already has comprehensive payment support:

```sql
-- Existing payment fields in deliveries table:
payment_by text null,                    -- 'sender' or 'recipient'
payment_method text null,                -- 'credit_card', 'maya_wallet', 'qr_ph', 'cash'
payment_status text null default 'pending', -- 'pending', 'paid', 'failed', 'cash_pending'
delivery_fee numeric(10, 2) null default 0.00,
tip_amount numeric(10, 2) null default 0.00,
total_amount numeric(10, 2) null default 0.00,
```

**✅ This means minimal Customer App changes required!**

---

## 🗃️ **NEW DATABASE SCHEMA CHANGES FOR DRIVER EARNINGS**

### **1. Enhanced `driver_earnings` Table**
We've added the following columns to support dual payment methods:

```sql
-- New columns added to driver_earnings table
ALTER TABLE driver_earnings 
ADD COLUMN payment_method VARCHAR(20) NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash', 'card'));

ALTER TABLE driver_earnings 
ADD COLUMN platform_commission NUMERIC(10,2) NOT NULL DEFAULT 0;

ALTER TABLE driver_earnings 
ADD COLUMN driver_net_earnings NUMERIC(10,2) NOT NULL DEFAULT 0;

ALTER TABLE driver_earnings 
ADD COLUMN is_remittance_required BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE driver_earnings 
ADD COLUMN remittance_deadline TIMESTAMP WITH TIME ZONE;

ALTER TABLE driver_earnings 
ADD COLUMN remittance_id UUID REFERENCES cash_remittances(id);

-- Performance index
CREATE INDEX idx_driver_earnings_payment_method ON driver_earnings(driver_id, payment_method);
```

### **2. New `driver_cash_balances` Table**
```sql
CREATE TABLE driver_cash_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID REFERENCES driver_profiles(id) UNIQUE,
  current_balance NUMERIC(10,2) NOT NULL DEFAULT 0,
  pending_remittance NUMERIC(10,2) NOT NULL DEFAULT 0,
  last_remittance_date TIMESTAMP WITH TIME ZONE NOT NULL,
  next_remittance_due TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_driver_cash_balances_driver ON driver_cash_balances(driver_id);
CREATE INDEX idx_driver_cash_balances_due_date ON driver_cash_balances(next_remittance_due);
```

### **3. New `cash_remittances` Table**
```sql
CREATE TABLE cash_remittances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID REFERENCES driver_profiles(id),
  amount NUMERIC(10,2) NOT NULL,
  status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'overdue')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  processed_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  paymaya_transaction_id VARCHAR(100),
  failure_reason TEXT,
  earnings_ids UUID[] NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_cash_remittances_driver ON cash_remittances(driver_id);
CREATE INDEX idx_cash_remittances_status ON cash_remittances(status);
CREATE INDEX idx_cash_remittances_created ON cash_remittances(created_at);
```

---

## 💰 **PAYMENT SYSTEM ARCHITECTURE**

### **Card Payments (PayMaya/Digital):**
- ✅ Platform takes **16% commission** immediately at transaction
- ✅ Driver receives **84%** automatically to PayMaya wallet
- ✅ **No cash remittance required** - funds are digital
- ✅ Instant payout after delivery completion
- ✅ `payment_method = 'card'`
- ✅ `is_remittance_required = false`

### **Cash Payments (COD):**
- ✅ Driver collects **100% cash** from customer
- ✅ Must remit **16% platform commission** within **24 hours**
- ✅ Keeps **84%** as net earnings
- ✅ **Requires cash remittance tracking**
- ✅ `payment_method = 'cash'`
- ✅ `is_remittance_required = true`
- ✅ `remittance_deadline = delivery_time + 24 hours`

---

## 🎯 **CUSTOMER APP INTEGRATION REQUIREMENTS**

### **✅ GREAT NEWS: Payment Method Already Exists!** 
The `deliveries` table already has payment method support with these constraints:

```sql
-- Existing payment_method constraint in deliveries table:
constraint deliveries_payment_method_check check (
  (
    payment_method = any (
      array[
        'credit_card'::text,
        'maya_wallet'::text,
        'qr_ph'::text,
        'cash'::text
      ]
    )
  )
)
```

### **Payment Method Mapping:**
- **Card Payments**: `'credit_card'`, `'maya_wallet'`, `'qr_ph'` → Driver App: `PaymentMethod.card`
- **Cash Payments**: `'cash'` → Driver App: `PaymentMethod.cash`

### **Database Queries - No Changes Needed:**

#### **1. Delivery Creation Flow:**
```dart
// Customer App - Payment method already supported
final delivery = await supabase.from('deliveries').insert({
  'customer_id': customerId,
  'pickup_address': pickupAddress,
  'delivery_address': deliveryAddress,
  'total_price': totalPrice,
  'payment_method': selectedPaymentMethod, // ALREADY EXISTS ✅
  'payment_status': 'pending',
  'vehicle_type_id': vehicleTypeId,
  // ... other fields
}).select().single();
```

#### **2. Driver Earnings Recording:**
The Driver App will record earnings based on existing payment method:

```dart
// Driver App - Payment method mapping
PaymentMethod getPaymentMethodFromDelivery(String? paymentMethod) {
  switch (paymentMethod) {
    case 'credit_card':
    case 'maya_wallet':
    case 'qr_ph':
      return PaymentMethod.card;
    case 'cash':
      return PaymentMethod.cash;
    default:
      return PaymentMethod.cash; // Default fallback
  }
}

// Updated earnings recording
await driverEarningsService.recordDeliveryEarnings(
  driverId: driverId,
  deliveryId: deliveryId,
  totalPrice: delivery.totalPrice,
  paymentMethod: getPaymentMethodFromDelivery(delivery.paymentMethod),
  tips: delivery.tipAmount ?? 0.0,
);
```

#### **3. Commission Calculation:**
```dart
// Both apps should use consistent commission calculation
final platformCommissionRate = 0.16; // 16%
final platformCommission = totalPrice * platformCommissionRate;
final driverNetEarnings = totalPrice - platformCommission;
```

---

## 🚨 **IMMEDIATE ACTION REQUIRED FROM CUSTOMER APP**

### **Phase 1: Database Schema Sync** (URGENT)
- [ ] **Apply all SQL schema changes** to your database
- [ ] **Test database migrations** in development environment
- [ ] **Verify table creation** and indexes

### **Phase 2: Payment Method Integration** (SIMPLIFIED ✅)
- [x] **Payment method field exists** in deliveries table ✅
- [ ] **Verify payment method selection** works in customer app UI
- [ ] **Confirm payment method values** are being set correctly
- [ ] **Test both card and cash payment flows**

### **Phase 3: UI Updates** (MEDIUM PRIORITY)
- [ ] **Add payment method toggle** in delivery creation screen
- [ ] **Show payment method** in delivery history
- [ ] **Display appropriate messaging** for card vs cash payments

---

## 🔄 **COORDINATION CHECKPOINTS**

### **Checkpoint 1: Database Schema** ✋
**BLOCKER:** We cannot proceed with Driver App testing until Customer App confirms:
- ✅ All database tables created successfully
- ✅ Schema changes applied without errors
- ✅ Indexes created for performance

### **Checkpoint 2: Payment Method Integration** ✅ SIMPLIFIED
**REQUIREMENT:** Driver App needs to verify:
- ✅ Customer App is setting `payment_method` field (already exists in schema)
- ✅ Payment method values match expected constraints
- ✅ Driver App can map payment methods correctly (`credit_card`/`maya_wallet`/`qr_ph` → card, `cash` → cash)

### **Checkpoint 3: Testing Coordination** ✋
**REQUIRED:** Joint testing scenarios:
- ✅ Create card payment delivery → Driver completes → Check digital payout
- ✅ Create cash payment delivery → Driver completes → Check remittance tracking
- ✅ Test commission calculations match between apps
- ✅ Verify 24-hour remittance countdown works

---

## 📱 **DRIVER APP FEATURES READY**

We have implemented but **CANNOT TEST** until Customer App coordination:

### **✅ Completed Features:**
- 💳 **Dual Payment Method Support** (card/cash)
- 📊 **Enhanced Earnings Tracking** with commission breakdown
- ⏰ **24-Hour Remittance System** for cash payments
- 💰 **Cash Balance Management**
- 🔔 **Remittance Deadline Alerts**
- 📈 **Separate Card vs Cash Earnings Dashboard**

### **🔄 Mock/Placeholder Features:**
- 💳 **PayMaya Integration** (placeholder - will implement after payment gateway setup)
- 💸 **Automatic Remittance Processing** (mock success for now)

---

## 🎯 **PROPOSED TIMELINE**

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| **Database Schema Sync** | 1-2 days | Customer App team applies SQL changes |
| **Payment Method Integration** | 2-3 days | Customer App adds payment selection UI |
| **Joint Testing** | 2-3 days | Both apps coordinate test scenarios |
| **PayMaya Integration** | 1-2 weeks | Business team provides PayMaya credentials |

---

## 🚀 **NEXT STEPS**

### **Customer App Team - SIMPLIFIED REQUIREMENTS:**
1. **Apply driver earnings database schema changes** (3 new tables + driver_earnings updates)
2. **Confirm payment method field is being used** in delivery creation
3. **Verify payment method values** match database constraints
4. **Test both card and cash deliveries** to ensure payment_method is set

### **Driver App Team - READY TO PROCEED:**
1. ✅ **Payment method integration simplified** - existing delivery table supports it
2. ✅ **Driver App updated** to map existing payment methods correctly
3. ✅ **Can begin testing** once database schema confirmed
4. 🚀 **Earnings system ready** for immediate implementation

---

## 📞 **CONTACT FOR COORDINATION**

**Driver App Team:** Ready for immediate coordination  
**Response Required:** Within 24 hours  
**Technical Questions:** Available for clarification on payment flow

---

**� MODERATE IMPACT:** This requires **database schema updates** for driver earnings tracking, but payment method integration is **already supported** in the deliveries table.

**SIMPLIFIED COORDINATION NEEDED:**
- ✅ Apply driver earnings database schema (3 new tables)  
- ✅ Confirm customer app is setting `payment_method` field correctly
- ✅ Test both card (`credit_card`/`maya_wallet`/`qr_ph`) and cash payments

Please confirm receipt and estimated timeline for database schema application.