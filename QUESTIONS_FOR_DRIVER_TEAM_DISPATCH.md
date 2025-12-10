# 🚗 Critical Questions for Driver Team - Business Dispatch Integration

**Date:** December 9, 2025  
**Context:** We're implementing Option A (Edge Function approach) for business dispatch assignment. We need to coordinate on several critical integration points to ensure the driver app can properly receive and handle business delivery assignments.

---

## 🔴 **CRITICAL: Assignment Discovery**

### **Question 1: How do drivers currently discover new assignments?**

We need to know your exact implementation:

**Option A: Polling (You mentioned this)**
- ✅ Do you poll the `deliveries` table every 30 seconds?
- ✅ What exact query do you use?
- ✅ Can you add a filter for `driver_source = 'business_dispatch'`?

**Current query (our assumption):**
```sql
SELECT * FROM deliveries
WHERE driver_id = {current_driver_id}
  AND status = 'driver_assigned'
ORDER BY assigned_at DESC
```

**Proposed enhanced query:**
```sql
SELECT * FROM deliveries
WHERE driver_id = {current_driver_id}
  AND status IN ('driver_assigned', 'pickup_arrived', 'package_collected', 'in_transit')
  AND driver_source = 'business_dispatch'  -- NEW FILTER
ORDER BY assigned_at DESC
```

**Option B: Realtime Subscriptions**
- ❓ Do you use Supabase Realtime subscriptions?
- ❓ What table/channel do you subscribe to?
- ❓ Can you add filters for `driver_id` and `driver_source`?

**Option C: Push Notifications (FCM)**
- ❓ Do you have FCM implemented?
- ❓ Do you upload `fcm_token` to `driver_profiles.fcm_token`?
- ❓ When do you upload it (on login, app launch)?
- ❓ Do you handle FCM messages in background/foreground?

**👉 OUR ASK:** Please confirm which method(s) you use and if you can add the `driver_source` filter.

---

## 🔴 **CRITICAL: Auto-Accept vs Manual Accept**

### **Question 2: Should business dispatch assignments be auto-accepted?**

For **business deliveries** (assigned by dispatcher), should the driver:

**Option A: Auto-Accept (RECOMMENDED)**
- ✅ When driver sees `status = 'driver_assigned'`, treat it as already accepted
- ✅ Skip the "Accept/Reject" buttons
- ✅ Show "Start Delivery" button immediately
- ✅ Dispatcher specifically chose this driver, so rejection doesn't make sense

**Option B: Manual Accept (Current B2C flow)**
- ❌ Driver sees "Accept/Reject" buttons
- ❌ If driver rejects, delivery goes back to `pending` status
- ❌ Dispatcher has to reassign to another driver
- ❌ More friction, but driver has choice

**👉 OUR RECOMMENDATION:** Auto-accept for business deliveries. The dispatcher manually selected this specific driver, so they should just start the delivery.

**👉 OUR ASK:** Confirm if you can implement auto-accept for `driver_source = 'business_dispatch'`.

---

## 🔴 **CRITICAL: Status Progression Flow**

### **Question 3: What is the exact status progression for business deliveries?**

We need to confirm the status flow and what triggers each change:

**Our Current Understanding:**
```
1. pending (business creates order)
   ↓
2. driver_assigned (dispatcher assigns driver)
   ↓ [Driver taps "Start Delivery" or "En Route to Pickup"]
3. pickup_arrived (driver arrives at pickup location)
   ↓ [Driver taps "Collect Package" or confirms collection]
4. package_collected (driver has the package)
   ↓ [Driver starts navigation to dropoff]
5. in_transit (driver is on the way to dropoff)
   ↓ [Driver arrives and confirms delivery]
6. delivered (package delivered successfully)
```

**Questions:**
- ❓ Is this flow correct?
- ❓ What button/action triggers each status change?
- ❓ Do you have a `pickup_arrived` status or do you go straight to `package_collected`?
- ❓ When does status change from `driver_assigned` to the next step?
- ❓ Do you update status via Supabase REST API or edge function?

**Status Update API (our assumption):**
```typescript
// Driver app calls:
await supabase
  .from('deliveries')
  .update({ 
    status: 'pickup_arrived',
    updated_at: new Date().toISOString()
  })
  .eq('id', delivery_id);
```

**👉 OUR ASK:** Please confirm the exact status flow and how you update each status.

---

## 🔴 **CRITICAL: Real-Time Location Tracking**

### **Question 4: When and how do drivers publish their location?**

For business admin to track drivers in real-time:

**Questions:**
- ❓ When do you start publishing location? (At `driver_assigned`? At `pickup_arrived`?)
- ❓ What technology do you use?
  - Ably Realtime?
  - Supabase Realtime?
  - Direct API calls?
- ❓ What channel/topic format?
  - `delivery:{delivery_id}`?
  - `driver:{driver_id}`?
  - Something else?
- ❓ How often do you publish? (Every 5 seconds? 10 seconds? On movement only?)
- ❓ Do you also update `driver_profiles.current_latitude` and `current_longitude`?

**Our Expected Flow:**
```typescript
// When driver starts delivery:
1. Driver taps "Start Delivery"
2. Driver app starts location tracking
3. Every 5-10 seconds, publish to Ably/Realtime:
   {
     driver_id: "uuid",
     delivery_id: "uuid",
     latitude: 14.5995,
     longitude: 120.9842,
     timestamp: "2025-12-09T10:30:00Z",
     heading: 90,
     speed: 25
   }
4. Also update driver_profiles table periodically
```

**👉 OUR ASK:** Please confirm your location tracking implementation so we can subscribe to the correct channel.

---

## 🟡 **IMPORTANT: Payment Collection (Marketplace Drivers Only)**

### **Question 5: How do marketplace drivers handle payment collection?**

For **marketplace drivers** (independent drivers, not fleet):

**Fields in `deliveries` table:**
- `payment_by` = 'sender' | 'recipient'
- `payment_method` = 'cash' | 'credit_card' | 'maya_wallet' | 'qr_ph'
- `payment_status` = 'pending' | 'paid' | 'failed'
- `total_price` = amount to collect

**Questions:**
- ❓ Do you show payment details in the driver app?
- ❓ When do drivers collect payment?
  - Before pickup (sender pays)?
  - After delivery (recipient pays)?
- ❓ How do drivers confirm payment collected?
  - Button in app "Confirm Payment Received"?
  - Automatic on delivery completion?
- ❓ Do you update `payment_status` from 'pending' to 'paid'?
- ❓ What happens if payment fails? Can driver still complete delivery?

**For Fleet Drivers:**
- `payment_status` = 'not_applicable' (they're employees, no payment needed)

**👉 OUR ASK:** Confirm your payment collection flow so we can coordinate completion logic.

---

## 🟡 **IMPORTANT: Fleet vs Marketplace Differentiation**

### **Question 6: Do you differentiate between fleet and marketplace deliveries in the UI?**

**Fields to check:**
- `driver_source` = 'fleet' | 'marketplace' | 'business_dispatch'
- `fleet_vehicle_id` = UUID (if fleet driver) or NULL (if marketplace)
- `payment_status` = 'not_applicable' (fleet) or 'pending'/'paid' (marketplace)

**Questions:**
- ❓ Do fleet drivers see different screens than marketplace drivers?
- ❓ Do fleet drivers skip payment collection screens?
- ❓ Do you show the business name who owns the fleet vehicle?
- ❓ Do you track fleet vehicle usage differently?

**👉 OUR ASK:** Let us know if we need to set any special flags for fleet vs marketplace drivers.

---

## 🟢 **NICE TO HAVE: FCM Push Notifications**

### **Question 7: When can we implement FCM push notifications?**

Our edge function (`assign-business-driver`) is ready to send FCM notifications but needs:

**Requirements:**
1. ✅ Driver app uploads `fcm_token` to `driver_profiles.fcm_token` on login
2. ✅ We set up Firebase Admin SDK in edge function
3. ✅ We send notification on assignment:
   ```json
   {
     "notification": {
       "title": "New Business Delivery Assigned",
       "body": "Pickup: ABC Company - ₱250.00"
     },
     "data": {
       "type": "business_delivery_assigned",
       "delivery_id": "uuid",
       "business_name": "ABC Company",
       "pickup_address": "123 Main St",
       "dropoff_address": "456 Oak Ave",
       "total_amount": "250.00",
       "auto_accept": "true"
     }
   }
   ```

**Questions:**
- ❓ Do you currently upload `fcm_token` to the database?
- ❓ Do you handle `business_delivery_assigned` notification type?
- ❓ When can you implement FCM if not already done?
- ❓ Should we prioritize this or is polling sufficient for now?

**👉 OUR ASK:** Let us know your FCM implementation status and timeline.

---

## 🟢 **NICE TO HAVE: Delivery Rejection Flow**

### **Question 8: What happens if a driver needs to reject a business delivery?**

**Scenarios:**
- Driver is suddenly unavailable (emergency, vehicle breakdown)
- Driver is too far from pickup
- Driver doesn't have capacity for the package size

**Current B2C Flow (our assumption):**
- Driver taps "Reject"
- Delivery goes back to `pending`
- System broadcasts to other drivers

**For Business Dispatch:**
- Dispatcher manually assigned this specific driver
- If driver rejects, who reassigns?
- Should we notify dispatcher?

**Proposed Flow:**
```
1. Driver taps "Cannot Complete Delivery"
2. Driver selects reason (optional)
3. Delivery status → 'pending' or 'rejected'
4. driver_id → NULL
5. driver_profiles.current_status → 'online'
6. Notify dispatcher (push notification or in-app alert)
7. Dispatcher sees delivery back in "Pending Dispatch"
8. Dispatcher reassigns to another driver
```

**👉 OUR ASK:** Confirm if you need rejection flow or if auto-accept means no rejection allowed.

---

## 📊 **Summary of Critical Dependencies**

### **Must Have Before We Deploy:**
1. ✅ Confirmation on assignment discovery method (polling with `driver_source` filter)
2. ✅ Confirmation on auto-accept vs manual accept for business deliveries
3. ✅ Exact status progression flow and how you update statuses
4. ✅ Real-time location tracking implementation (channel format, frequency)

### **Important But Can Come Later:**
5. 🟡 Payment collection flow for marketplace drivers
6. 🟡 Fleet vs marketplace differentiation in UI
7. 🟡 FCM push notification implementation
8. 🟡 Delivery rejection flow

---

## 🚀 **Next Steps**

**After you answer these questions:**
1. We'll implement Option A (enhanced edge function)
2. We'll refactor dispatch page to use edge function
3. We'll build real-time tracking page (subscribing to your location channel)
4. We'll coordinate testing with a test driver account
5. We'll deploy and monitor production

**Timeline Estimate:**
- Edge function enhancement: 2 hours
- Dispatch page refactor: 1 hour
- Testing: 1 hour
- Total: **4 hours** (once we have your answers)

---

## 📧 **How to Respond**

Please answer each question with:
- ✅ Yes/Confirmed
- ❌ No/Not implemented
- 🔄 In progress (ETA: date)
- ❓ Need clarification

**Example:**
> **Question 1:** We poll every 30 seconds ✅  
> **Question 2:** We can implement auto-accept for business deliveries ✅  
> **Question 3:** Status flow is correct, we update via REST API ✅  
> **Question 4:** We use Ably with channel `delivery:{delivery_id}` ✅  

---

**Thank you for coordinating with us! This will ensure smooth integration between business admin web app and driver mobile app.** 🙏
