# 🚗 Driver Team Answers - Business Dispatch Integration

**Date:** December 9, 2025  
**Driver App:** SwiftDash Driver (Flutter)  
**Team Member:** Driver Team  

---

## ✅ **CRITICAL ANSWERS**

### **Question 1: How do drivers currently discover new assignments?**

**✅ We use Supabase Realtime subscriptions** (not polling)

**Implementation Details:**
- **Channel:** `driver-deliveries-{driver_id}`
- **Technology:** Supabase Realtime Postgres Changes
- **File:** `lib/services/realtime_service.dart` (line 53)
- **Filters:** 
  - `driver_id = {current_driver_id}` 
  - `status = 'driver_offered'` (for new offers)
  - Event type: `PostgresChangeEvent.all`

**Code Reference:**
```dart
// We subscribe to deliveries channel on driver login
channel.onPostgresChanges(
  event: PostgresChangeEvent.all,
  schema: 'public',
  table: 'deliveries',
  filter: PostgresChangeFilter(
    type: PostgresChangeFilterType.eq,
    column: 'driver_id',
    value: driverId,
  ),
  callback: (payload) => _handleDriverDeliveryUpdate(payload),
);

// Separate listener for new offers (status = 'driver_offered')
channel.onPostgresChanges(
  event: PostgresChangeEvent.update,
  schema: 'public',
  table: 'deliveries',
  filter: PostgresChangeFilter(
    type: PostgresChangeFilterType.eq,
    column: 'status',
    value: 'driver_offered',
  ),
  callback: (payload) => _handleNewDeliveryOffer(payload),
);
```

**✅ Can we add `driver_source` filter?**
- **YES** - We already have `driver_source` field in our `Delivery` model
- **File:** `lib/models/delivery.dart` (line 186)
- **Getter:** `bool get isBusinessDispatch => driverSource == 'business_dispatch';`
- We can easily add conditional logic based on this field

**❌ FCM Push Notifications:**
- **NOT CURRENTLY IMPLEMENTED**
- We don't have `fcm_token` upload to database yet
- We rely on Supabase Realtime + Ably for real-time updates
- **Timeline:** Can implement FCM in ~1 week if needed

---

### **Question 2: Should business dispatch assignments be auto-accepted?**

**✅ CONFIRMED: We will implement auto-accept for business deliveries**

**Current Flow (B2C):**
- Driver sees modal with "Accept" / "Decline" buttons
- File: `lib/widgets/improved_delivery_offer_modal.dart`

**Proposed Flow (Business Dispatch):**
```dart
// Pseudo-code for implementation
if (delivery.isBusinessDispatch) {
  // Auto-accept: Skip modal, go straight to active delivery
  await _acceptDelivery(delivery);
  _showActiveDeliveryPanel(delivery);
} else {
  // B2C: Show accept/decline modal
  _showOfferModal(delivery);
}
```

**Timeline:** Can implement in ~2 hours

**Reasoning:** 
- Dispatcher specifically chose this driver
- No need for rejection flow in MVP
- Reduces friction and time-to-pickup

---

### **Question 3: What is the exact status progression for business deliveries?**

**✅ CONFIRMED: Our status flow is:**

```
1. pending
   ↓ (dispatcher assigns)
2. driver_assigned
   ↓ [Driver taps "Start Delivery" - auto-accept for business]
3. pickup_arrived  
   ↓ [Driver taps "Confirm Package Collection"]
4. package_collected
   ↓ [Driver starts navigation to delivery]
5. in_transit
   ↓ [Driver arrives and taps "Complete Delivery"]
6. delivered
```

**Status Update Implementation:**
- **Method:** Supabase REST API (direct table update)
- **File:** `lib/services/driver_flow_service.dart` and `lib/widgets/draggable_delivery_panel.dart`

**Code Reference:**
```dart
// Example status update
await supabase
  .from('deliveries')
  .update({
    'status': 'pickup_arrived',
    'updated_at': DateTime.now().toIso8601String(),
  })
  .eq('id', delivery.id);
```

**Button Triggers:**
- `driver_assigned` → `pickup_arrived`: "Start Delivery" button (auto-trigger on navigation)
- `pickup_arrived` → `package_collected`: "Confirm Package Collection" button
- `package_collected` → `in_transit`: Automatic when driver starts navigation
- `in_transit` → `delivered`: "Complete Delivery" button (with proof of delivery)

**Additional Ably Events** (for real-time customer updates):
- `going_to_pickup` (non-persistent, Ably only)
- `at_pickup` (non-persistent, Ably only)
- All persistent statuses are written to database

---

### **Question 4: When and how do drivers publish their location?**

**✅ We use Ably Realtime** (not Supabase Realtime for location)

**Implementation Details:**
- **Start Time:** When delivery status changes to `driver_assigned`
- **Technology:** Ably Realtime
- **Channel Format:** `tracking:{delivery_id}`
- **Event Name:** `location-update`
- **Frequency:** Every 3-5 seconds (configurable)
- **File:** `lib/services/ably_service.dart` (line 103)

**Location Payload:**
```dart
{
  'latitude': 14.5995,
  'longitude': 120.9842,
  'timestamp': '2025-12-09T10:30:00Z',
  'heading': 90.0,       // degrees (0-360)
  'speed': 25.5,         // km/h
  'accuracy': 5.0,       // meters
  'battery_level': 85,   // percentage
}
```

**Code Reference:**
```dart
// Publish location via Ably
await AblyService().publishLocation(deliveryId, {
  'latitude': position.latitude,
  'longitude': position.longitude,
  'timestamp': DateTime.now().toIso8601String(),
  'heading': position.heading,
  'speed': position.speed * 3.6, // m/s to km/h
  'accuracy': position.accuracy,
});
```

**Database Updates:**
- We do NOT continuously update `driver_profiles.current_latitude/longitude`
- We only update database location when driver goes online/offline
- All real-time tracking uses Ably channels only (to reduce database writes)

**Presence:**
- We use Ably Presence to indicate driver is "online" on the channel
- When driver starts delivery, we call `channel.presence.enter()`
- When delivery completes, we call `channel.presence.leave()`

---

## 🟡 **IMPORTANT ANSWERS**

### **Question 5: How do marketplace drivers handle payment collection?**

**🔄 PARTIALLY IMPLEMENTED** - Payment collection UI exists but needs refinement

**Current Implementation:**
- Payment details are shown in delivery panel
- Fields: `payment_by`, `payment_method`, `payment_status`, `total_price`
- **File:** `lib/widgets/draggable_delivery_panel.dart`

**Collection Flow:**
- If `payment_by = 'recipient'`: Driver collects cash/confirms payment after delivery
- If `payment_by = 'sender'`: Payment already collected (pre-paid)

**Status Update:**
```dart
// On delivery completion
await supabase
  .from('deliveries')
  .update({
    'payment_status': 'paid', // or 'failed'
    'status': 'delivered',
  })
  .eq('id', delivery.id);
```

**For Fleet Drivers:**
- `payment_status` remains `null` or `'not_applicable'`
- They don't see payment collection UI
- File: We check `driver_source` and `fleet_vehicle_id` to hide payment screens

**Timeline:** Can polish payment collection UI in ~2 hours if needed

---

### **Question 6: Do you differentiate between fleet and marketplace deliveries in the UI?**

**✅ YES** - We have conditional UI logic

**Fields We Check:**
- `driver_source`: 'fleet' | 'marketplace' | 'business_dispatch'
- `fleet_vehicle_id`: UUID (fleet) or NULL (marketplace)
- `payment_status`: Used to determine if payment collection is needed

**Current Differentiation:**
```dart
// Example logic (pseudo-code)
if (delivery.driverSource == 'fleet' || delivery.fleetVehicleId != null) {
  // Fleet driver: Skip payment collection
  hidePaymentUI();
} else {
  // Marketplace driver: Show payment collection
  showPaymentUI();
}
```

**Business Name Display:**
- We can show business name from `businesses` table join
- Currently not displayed, but easy to add

**Vehicle Tracking:**
- Fleet drivers have `fleet_vehicle_id` linked to `fleet_vehicles` table
- We can track vehicle-specific metrics if needed

**Timeline:** Can enhance fleet/marketplace differentiation in ~1 hour

---

## 🟢 **NICE TO HAVE ANSWERS**

### **Question 7: When can we implement FCM push notifications?**

**❌ NOT CURRENTLY IMPLEMENTED**

**What We Need:**
1. ❌ Add `fcm_token` field upload on login
2. ❌ Install `firebase_messaging` Flutter package
3. ❌ Configure Firebase project (iOS + Android)
4. ❌ Handle FCM message payloads in app

**Timeline:**
- Research & setup: ~2 hours
- Implementation: ~4 hours
- Testing: ~2 hours
- **Total: ~8 hours (~1 working day)**

**Priority:**
- **Low Priority for MVP** - Supabase Realtime works well for real-time delivery assignment
- **Medium Priority for Production** - Would be good for offline/background scenarios
- We can implement this after MVP launch if needed

---

### **Question 8: What happens if a driver needs to reject a business delivery?**

**✅ CURRENT B2C FLOW:** Driver can tap "Decline" button

**Proposed Business Flow:**
- **Option A (Recommended):** No rejection for business deliveries (auto-accept only)
- **Option B:** Allow rejection with mandatory reason:

```dart
// Pseudo-code for rejection flow
if (delivery.isBusinessDispatch) {
  // Show rejection reason dialog
  final reason = await _showRejectionReasonDialog();
  
  if (reason != null) {
    await supabase
      .from('deliveries')
      .update({
        'status': 'pending',
        'driver_id': null,
        'rejection_reason': reason,
        'rejected_at': DateTime.now().toIso8601String(),
      })
      .eq('id', delivery.id);
    
    // Notify dispatcher via Ably or edge function
    await _notifyDispatcherOfRejection(delivery, reason);
  }
}
```

**Our Recommendation:**
- **Start with auto-accept only (no rejection)** for MVP
- Add rejection flow later if dispatchers request it

**Timeline:** 
- No rejection: 0 hours (auto-accept only)
- With rejection: ~2 hours to implement

---

## 📊 **Technical Summary**

### **Our Stack:**
- **Frontend:** Flutter (iOS + Android)
- **Backend:** Supabase (PostgreSQL + Realtime)
- **Real-time:** Ably (location tracking) + Supabase Realtime (delivery updates)
- **State Management:** Provider + Singleton services
- **Location:** Geolocator plugin (GPS)

### **Key Files:**
- Assignment discovery: `lib/services/realtime_service.dart`
- Location tracking: `lib/services/ably_service.dart`
- Delivery panel: `lib/widgets/draggable_delivery_panel.dart`
- Delivery model: `lib/models/delivery.dart`
- Main map screen: `lib/screens/main_map_screen.dart`

---

## 🚀 **Our Commitments**

### **✅ COMPLETED:**
1. ✅ ~~Add `driver_source = 'business_dispatch'` filter in subscriptions~~ **DONE** - Filter handled at application level via `delivery.isBusinessDispatch`
2. ✅ ~~Implement auto-accept for business deliveries~~ **DONE** - Implemented in `main_map_screen.dart` with `_handleBusinessDispatchAutoAccept()`
3. ✅ Ensure proper status progression and Ably events (already working)
4. ✅ Confirm Ably channel format: `tracking:{delivery_id}` (already implemented)

### **Implementation Details:**
- **File Modified:** `lib/screens/main_map_screen.dart`
  - Added `_handleBusinessDispatchAutoAccept()` method
  - Modified offer stream listener to check `delivery.isBusinessDispatch`
  - Auto-accepts business deliveries without showing modal
  - Shows success notification to driver
  
- **File Modified:** `lib/services/realtime_service.dart`
  - Added documentation about driver_source filtering
  - Filter handled at app level for flexibility

### **We Can Deliver:**
1. ✅ Testing with business dispatch deliveries (ready for integration)
2. ✅ Polish payment collection UI if needed (2 hours)
3. ✅ Enhance fleet/marketplace differentiation if needed (1 hour)

### **We Need from Web Team:**
1. ⏳ Confirmation that dispatcher creates delivery with:
   - `status = 'driver_assigned'`
   - `driver_id = {selected_driver_id}`
   - `driver_source = 'business_dispatch'`
   - `assigned_at = {timestamp}`
2. ⏳ Confirmation that web team subscribes to Ably channel `tracking:{delivery_id}`
3. ⏳ Test driver account credentials for integration testing

---

## 📅 **Timeline**

**Ready for Integration Testing:** 
- **4 hours** after we receive web team confirmation on delivery creation format

**Production Ready:**
- **1 day** after successful integration testing

---

## 📧 **Contact**

For any clarifications or technical discussions, please reach out to:
- **Driver Team Lead:** [Your Name]
- **Email:** [Your Email]
- **Slack:** @driver-team

**We're excited to integrate with the Business Dispatch system! 🚀**
