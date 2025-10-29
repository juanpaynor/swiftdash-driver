# 📊 Status Update Flow - Customer App Tracking System

**Audience**: Driver App Developer  
**Date**: October 29, 2025  
**Purpose**: Explain how status updates work in the customer tracking screen

---

## 🎯 TL;DR - What You Need to Know

The **customer app does NOT poll Supabase** for status updates during active tracking.

Instead, it uses **Ably real-time WebSocket** to receive instant updates from your driver app.

---

## 🔄 Complete Status Update Flow

### **Step 1: Driver App Publishes Status Change**

When the driver changes the delivery status (e.g., picks up package), your driver app should publish to Ably:

```dart
// Driver app code (what YOU need to implement)
await ablyChannel.publish('status-update', {
  'delivery_id': deliveryId,
  'status': 'package_collected',  // New status
  'timestamp': DateTime.now().toIso8601String(),
});
```

### **Step 2: Ably Broadcasts to Customer App**

Ably instantly pushes the update to all subscribers (customer app listening on that channel).

### **Step 3: Customer App Receives & Updates UI**

```dart
// Customer app code (already implemented)
_statusUpdateSubscription = _realtimeService.statusUpdateStream.listen(
  (statusData) {
    _updateDeliveryStatus(statusData);  // ✨ Instant UI update!
  }
);
```

### **Step 4: Customer Sees Update Immediately**

- Status banner changes
- Toast notification appears
- UI updates (e.g., "Driver picked up your package!")
- Route recalculates if needed

---

## 📡 Ably Channel Architecture

### **Channel Name Format**
```
tracking:{deliveryId}
```

**Example**: `tracking:550e8400-e29b-41d4-a716-446655440000`

### **Events Published on This Channel**

| **Event Name** | **Purpose** | **Frequency** | **Published By** |
|---------------|-------------|---------------|------------------|
| `location-update` | Driver GPS coordinates | Every 3-5 seconds | Driver App |
| `status-update` | Delivery status changes | On status change | Driver App |
| Presence (enter/leave) | Driver online/offline | On connect/disconnect | Driver App |

---

## 🚦 Status Values & Their Meanings

### **Status Progression**

```
pending
  ↓
driver_assigned (driver accepts job)
  ↓
going_to_pickup (driver en route to pickup)
  ↓
at_pickup (driver arrived at pickup)
  ↓
package_collected (driver picked up package)
  ↓
in_transit (driver delivering to customer)
  ↓
delivered (package dropped off)
```

### **What Customer Sees for Each Status**

| **Status** | **Customer Notification** | **UI Behavior** |
|-----------|--------------------------|-----------------|
| `pending` | "Searching for driver..." | Loading state |
| `driver_assigned` | "Driver found!" | Shows driver card |
| `going_to_pickup` | "Driver heading to pickup" | Blue route: Driver → Pickup |
| `at_pickup` | "Driver arrived at pickup" | Toast notification |
| `package_collected` | "Package picked up!" | Purple route: Driver → Customer |
| `in_transit` | "On the way!" | Real-time ETA updates |
| `delivered` | "Delivered! ✅" | Navigate to completion screen |

---

## 💻 Driver App Implementation Requirements

### **1. Initialize Ably Client**

```dart
import 'package:ably_flutter/ably_flutter.dart' as ably;

// Initialize with your Ably API key
final realtimeClient = ably.Realtime(
  key: 'YOUR_ABLY_KEY_HERE',
  clientId: 'driver_${driverId}',
);
```

### **2. Get Channel for Delivery**

```dart
final channelName = 'tracking:$deliveryId';
final channel = realtimeClient.channels.get(channelName);
```

### **3. Publish Location Updates (Every 3-5 seconds)**

```dart
await channel.publish('location-update', {
  'delivery_id': deliveryId,
  'latitude': currentLat,
  'longitude': currentLng,
  'timestamp': DateTime.now().toIso8601String(),
  'bearing': currentBearing,        // Heading in degrees
  'speed': currentSpeed,            // Speed in m/s
  'accuracy': gpsAccuracy,          // GPS accuracy in meters
  'battery_level': batteryPercentage, // Device battery %
});
```

### **4. Publish Status Updates (When Status Changes)**

```dart
// When driver picks up package
await channel.publish('status-update', {
  'delivery_id': deliveryId,
  'status': 'package_collected',
  'timestamp': DateTime.now().toIso8601String(),
});

// When driver starts delivering
await channel.publish('status-update', {
  'delivery_id': deliveryId,
  'status': 'in_transit',
  'timestamp': DateTime.now().toIso8601String(),
});

// When driver completes delivery
await channel.publish('status-update', {
  'delivery_id': deliveryId,
  'status': 'delivered',
  'timestamp': DateTime.now().toIso8601String(),
});
```

### **5. Enter Presence (Driver Online)**

```dart
// When driver starts tracking a delivery
await channel.presence.enter({
  'driver_id': driverId,
  'name': driverName,
  'vehicle_type': vehicleType,
});

// When driver finishes or goes offline
await channel.presence.leave();
```

---

## 🗄️ Database vs Ably - When to Use Each

### **❌ DON'T Use Supabase Database For:**

- ❌ Real-time location updates (too slow, polling is inefficient)
- ❌ Status changes during active delivery (customer wouldn't see instant updates)
- ❌ Checking if driver is online (use Ably presence instead)

### **✅ DO Use Supabase Database For:**

- ✅ **Initial delivery details** (pickup/delivery addresses, customer info)
- ✅ **Final status persistence** - When delivery is `delivered`, UPDATE database:
  ```sql
  UPDATE deliveries 
  SET status = 'delivered', 
      completed_at = NOW() 
  WHERE id = delivery_id;
  ```
- ✅ **Driver profile info** (name, vehicle, rating - rarely changes)
- ✅ **Historical data** (past deliveries, analytics)
- ✅ **Proof of delivery** (photos, signatures - stored after completion)

---

## 🔥 Critical: When to Update the Database

### **Only Write to Database When:**

1. **Delivery Completed**
   ```dart
   // Driver app: After publishing 'delivered' via Ably
   await supabase
     .from('deliveries')
     .update({
       'status': 'delivered',
       'completed_at': DateTime.now().toIso8601String(),
     })
     .eq('id', deliveryId);
   ```

2. **Delivery Cancelled**
   ```dart
   await supabase
     .from('deliveries')
     .update({
       'status': 'cancelled',
       'cancelled_at': DateTime.now().toIso8601String(),
       'cancellation_reason': reason,
     })
     .eq('id', deliveryId);
   ```

3. **Delivery Failed**
   ```dart
   await supabase
     .from('deliveries')
     .update({
       'status': 'failed',
       'failed_at': DateTime.now().toIso8601String(),
       'failure_reason': reason,
     })
     .eq('id', deliveryId);
   ```

### **❌ Do NOT Write Intermediate Statuses to Database**

Don't update database for these (Ably is enough):
- ❌ `going_to_pickup`
- ❌ `at_pickup`
- ❌ `package_collected`
- ❌ `in_transit`

**Why?** These are temporary states. Customer app uses Ably for real-time updates. Database writes are slow and unnecessary.

---

## 📊 Architecture Diagram

```
┌─────────────────┐
│   Driver App    │
│                 │
│  [GPS Service]  │
│       ↓         │
│  [Ably Publish] │
└────────┬────────┘
         │
         │ WebSocket
         ↓
┌─────────────────┐
│  Ably Service   │
│  (Cloud Server) │
│                 │
│  tracking:uuid  │
└────────┬────────┘
         │
         │ WebSocket
         ↓
┌─────────────────┐
│  Customer App   │
│                 │
│ [Ably Subscribe]│
│       ↓         │
│   [UI Update]   │
│                 │
│  ✨ INSTANT! ✨ │
└─────────────────┘

Database (Supabase)
       ↑
       │ Only on:
       │ - Initial load
       │ - Final status
       └─────────────
```

---

## 🧪 Testing Your Implementation

### **Test 1: Location Updates**

1. Driver app publishes location every 5 seconds
2. Customer app should see driver marker moving smoothly
3. Check browser console for: `📍 Received location update`

### **Test 2: Status Updates**

1. Driver changes status to `package_collected`
2. Customer app should show toast: "Package picked up!"
3. Check browser console for: `📊 Delivery status changed to: package_collected`

### **Test 3: Driver Presence**

1. Driver enters presence (goes online)
2. Customer app should show: "Driver is online"
3. Driver leaves presence (goes offline)
4. Customer app should show: "Driver went offline"

### **Test 4: Completed Delivery**

1. Driver publishes status: `delivered`
2. Customer sees notification
3. Customer app auto-navigates to completion screen
4. **Verify database updated**: Check `deliveries` table has `status = 'delivered'`

---

## 🐛 Common Issues & Solutions

### **Issue 1: Customer Not Receiving Updates**

**Symptoms**: Customer sees "Searching..." indefinitely

**Check**:
- ✅ Driver app connected to Ably?
- ✅ Publishing to correct channel? `tracking:{deliveryId}`
- ✅ Event name correct? `location-update` or `status-update`
- ✅ Payload format correct? (must be Map<String, dynamic>)

**Solution**:
```dart
// Verify channel name matches
print('Publishing to: tracking:$deliveryId');

// Check connection
print('Ably connected: ${realtimeClient.connection.state}');
```

### **Issue 2: Updates Delayed**

**Symptoms**: Updates take 5-10 seconds to appear

**Cause**: Publishing too infrequently or network issues

**Solution**:
- Publish location every 3-5 seconds (not 10+)
- Check driver's internet connection
- Verify Ably service status

### **Issue 3: Wrong Status Displayed**

**Symptoms**: Customer sees wrong status

**Cause**: Mismatch between Ably and database

**Solution**:
- Customer app uses Ably status (not database) during tracking
- Only update database on completion
- Don't manually update database during active delivery

---

## 📝 Driver App Checklist

Before going live, verify:

- [ ] Ably client initialized with valid API key
- [ ] GPS service running (location permissions granted)
- [ ] Publishing location every 3-5 seconds to `location-update` event
- [ ] Publishing status changes to `status-update` event
- [ ] Entering presence when starting delivery
- [ ] Leaving presence when finishing delivery
- [ ] Writing to database only when `delivered` or `cancelled`
- [ ] Payload format matches customer app expectations
- [ ] Tested with actual delivery (not just mock data)
- [ ] Error handling for network failures
- [ ] Battery optimization (don't drain device)

---

## 🔗 Related Documentation

- [Ably Flutter SDK](https://github.com/ably/ably-flutter)
- [Customer App Status Flow](./tracking_screen.dart) - See `_subscribeToUpdates()` method
- [Ably Channel Docs](https://ably.com/docs/channels)
- [Push Notification Plan](./PUSH_NOTIFICATIONS_PLAN.md) - For background notifications

---

## ❓ Questions?

**Why not use Supabase Realtime?**
- Ably is faster (optimized for GPS tracking)
- Better presence features (online/offline detection)
- More reliable for high-frequency updates

**What if Ably goes down?**
- Customer app will show "Connection lost"
- Location updates stop, but app remains functional
- Database still has last known status

**How much does Ably cost?**
- Free tier: 3 million messages/month
- Typical delivery: ~200 location updates = 200 messages
- Can handle ~15,000 deliveries/month on free tier

**Can I use Firebase instead?**
- Possible, but requires customer app changes
- Ably is already integrated and optimized
- Stick with Ably for consistency

---

## 🚀 Quick Start Example

```dart
// Driver App - Minimal Implementation

import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:geolocator/geolocator.dart';

class DeliveryTrackingService {
  late ably.Realtime _ably;
  late ably.RealtimeChannel _channel;
  
  Future<void> startTracking(String deliveryId) async {
    // 1. Initialize Ably
    _ably = ably.Realtime(key: 'YOUR_ABLY_KEY');
    _channel = _ably.channels.get('tracking:$deliveryId');
    
    // 2. Enter presence
    await _channel.presence.enter({'driver_id': 'driver_123'});
    
    // 3. Start GPS tracking
    Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((position) {
      // 4. Publish location
      _channel.publish('location-update', {
        'delivery_id': deliveryId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
        'bearing': position.heading,
        'speed': position.speed,
        'accuracy': position.accuracy,
      });
    });
  }
  
  Future<void> updateStatus(String deliveryId, String status) async {
    // 5. Publish status change
    await _channel.publish('status-update', {
      'delivery_id': deliveryId,
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    // 6. If delivered, update database
    if (status == 'delivered') {
      await Supabase.instance.client
        .from('deliveries')
        .update({'status': 'delivered', 'completed_at': 'now()'})
        .eq('id', deliveryId);
    }
  }
  
  Future<void> stopTracking() async {
    // 7. Leave presence
    await _channel.presence.leave();
    await _ably.close();
  }
}
```

---

**Summary**: Use Ably for real-time updates, Supabase for persistence. Customer app listens to Ably, not database. 🚀
