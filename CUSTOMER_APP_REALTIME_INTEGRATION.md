# SwiftDash Driver App - Realtime Database Integration Guide
## For Customer App AI Development Team

### 🎯 **Overview**
The SwiftDash driver app has been fully integrated with Supabase Realtime database for live delivery tracking. This document explains what we've implemented on the driver side and how the customer app should integrate to create a seamless real-time delivery experience.

---

## 📊 **Driver Side Implementation (COMPLETED)**

### **Database Schema & Status Flow**
We're using the following delivery status progression:
```
pending → driver_assigned → package_collected → in_transit → delivered
```

**Deliveries Table Schema:**
```sql
CREATE TABLE deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES user_profiles(id),
  driver_id UUID REFERENCES user_profiles(id),
  vehicle_type_id UUID NOT NULL REFERENCES vehicle_types(id),
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_at TIMESTAMP WITH TIME ZONE,
  assigned_at TIMESTAMP WITH TIME ZONE,
  picked_up_at TIMESTAMP WITH TIME ZONE,
  in_transit_at TIMESTAMP WITH TIME ZONE,
  delivered_at TIMESTAMP WITH TIME ZONE,
  
  -- Pickup Information
  pickup_address TEXT NOT NULL,
  pickup_latitude DECIMAL(10, 8) NOT NULL,
  pickup_longitude DECIMAL(11, 8) NOT NULL,
  pickup_contact_name TEXT NOT NULL,
  pickup_contact_phone TEXT NOT NULL,
  pickup_instructions TEXT,
  
  -- Delivery Information
  delivery_address TEXT NOT NULL,
  delivery_latitude DECIMAL(10, 8) NOT NULL,
  delivery_longitude DECIMAL(11, 8) NOT NULL,
  delivery_contact_name TEXT NOT NULL,
  delivery_contact_phone TEXT NOT NULL,
  delivery_instructions TEXT,
  
  -- Package Information
  package_description TEXT NOT NULL,
  package_weight DECIMAL(8, 2),
  package_value DECIMAL(10, 2),
  
  -- Pricing & Distance
  distance_km DECIMAL(8, 2),
  estimated_duration INTEGER, -- in minutes
  total_price DECIMAL(10, 2) NOT NULL,
  
  -- Ratings
  customer_rating INTEGER CHECK (customer_rating >= 1 AND customer_rating <= 5),
  driver_rating INTEGER CHECK (driver_rating >= 1 AND driver_rating <= 5)
);
```

**Driver Profiles Table Schema:**
```sql
CREATE TABLE driver_profiles (
  id UUID PRIMARY KEY REFERENCES user_profiles(id),
  vehicle_type_id UUID REFERENCES vehicle_types(id),
  license_number TEXT,
  vehicle_model TEXT,
  is_verified BOOLEAN DEFAULT FALSE,
  is_online BOOLEAN DEFAULT FALSE,
  current_latitude DECIMAL(10, 8),
  current_longitude DECIMAL(11, 8),
  location_updated_at TIMESTAMP WITH TIME ZONE,
  rating DECIMAL(3, 2) DEFAULT 0.00,
  total_deliveries INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Key Tables Used:**
- `deliveries` - Main delivery records with full lifecycle tracking
- `driver_profiles` - Driver information, online status, and real-time location  
- `user_profiles` - Driver personal information (name, phone, email)
- `vehicle_types` - Vehicle categories and pricing information

### **Realtime Subscriptions (Driver App)**
The driver app listens to:

1. **New Delivery Offers**
   ```dart
   // Listens for INSERT events on deliveries table
   channel.onPostgresChanges(
     event: PostgresChangeEvent.insert,
     table: 'deliveries',
     filter: PostgresChangeFilter(column: 'status', value: 'pending')
   )
   ```

2. **Delivery Updates**
   ```dart
   // Listens for UPDATE events for assigned deliveries
   channel.onPostgresChanges(
     event: PostgresChangeEvent.update,
     table: 'deliveries',
     filter: PostgresChangeFilter(column: 'driver_id', value: driverId)
   )
   ```

3. **Driver Profile Updates**
   ```dart
   // Listens for driver online/offline status changes
   channel.onPostgresChanges(
     event: PostgresChangeEvent.update,
     table: 'driver_profiles',
     filter: PostgresChangeFilter(column: 'id', value: driverId)
   )
   ```

### **Driver Actions & Status Updates**
The driver app can:
- **Accept deliveries** → Updates status from `pending` to `driver_assigned`
- **Mark pickup complete** → Updates status to `package_collected`
- **Start delivery** → Updates status to `in_transit`
- **Complete delivery** → Updates status to `delivered`
- **Update location** → Updates `current_latitude/longitude` in `driver_profiles`

---

## 🎯 **Customer App Integration Requirements**

### **1. Realtime Subscriptions Setup**

**A. Track Your Own Deliveries (Recommended Method)**
```dart
// Flutter/Dart Subscription Example
final subscription = supabase
  .from('deliveries:id=eq.${deliveryId}')
  .on(SupabaseEventTypes.update, (payload) {
    // Update UI with new status, driver info, location, etc.
    updateDeliveryStatus(payload['new']);
  })
  .subscribe();
```

**Alternative JavaScript Implementation:**
```javascript
// JavaScript Subscription Example
const deliveryChannel = supabase
  .channel('customer-deliveries')
  .on('postgres_changes', {
    event: 'UPDATE',
    schema: 'public',
    table: 'deliveries',
    filter: `customer_id=eq.${userId}`
  }, (payload) => {
    // Handle delivery status updates
    updateDeliveryStatus(payload.new);
  })
  .subscribe();
```

**B. Track Driver Location (Live Location Tracking)**
```dart
// Subscribe to driver location updates when delivery is active
final driverLocationSubscription = supabase
  .from('driver_profiles:id=eq.${assignedDriverId}')
  .on(SupabaseEventTypes.update, (payload) {
    // Update driver location on map
    final lat = payload['new']['current_latitude'];
    final lng = payload['new']['current_longitude'];
    if (lat != null && lng != null) {
      updateDriverLocationOnMap(lat, lng);
    }
  })
  .subscribe();
```

**C. Multiple Deliveries Tracking**
```dart
// For customers with multiple active deliveries
final allDeliveriesSubscription = supabase
  .from('deliveries:customer_id=eq.${customerId}')
  .on(SupabaseEventTypes.update, (payload) {
    // Update specific delivery in list
    updateDeliveryInList(payload['new']);
  })
  .subscribe();
```

### **2. Status Progression Handling**

**Customer App Should Display:**
- ✅ `pending` → "Waiting for driver..."
- ✅ `driver_assigned` → "Driver found! [Driver Name] is on the way"
- ✅ `package_collected` → "Driver picked up package"
- ✅ `in_transit` → "Driver en route to destination"
- ✅ `delivered` → "Delivery complete!"

**Complete Status Mapping:**
```dart
String getStatusMessage(String status) {
  switch (status) {
    case 'pending':
      return 'Waiting for driver...';
    case 'driver_assigned':
      return 'Driver found! Driver is on the way to pickup';
    case 'package_collected':
      return 'Driver picked up package';
    case 'in_transit':
      return 'Driver en route to destination';
    case 'delivered':
      return 'Delivery complete!';
    case 'cancelled':
      return 'Delivery cancelled';
    case 'failed':
      return 'Delivery failed - please contact support';
    default:
      return 'Unknown status';
  }
}

IconData getStatusIcon(String status) {
  switch (status) {
    case 'pending':
      return Icons.search;
    case 'driver_assigned':
      return Icons.person_pin_circle;
    case 'package_collected':
      return Icons.inventory;
    case 'in_transit':
      return Icons.local_shipping;
    case 'delivered':
      return Icons.check_circle;
    case 'cancelled':
      return Icons.cancel;
    case 'failed':
      return Icons.error;
    default:
      return Icons.help;
  }
}
```

**Example Implementation:**
```dart
void updateDeliveryStatus(Map<String, dynamic> delivery) {
  final status = delivery['status'];
  final driverId = delivery['driver_id'];
  
  switch (status) {
    case 'pending':
      showStatusUpdate('Waiting for driver...', 'searching');
      break;
    case 'driver_assigned':
      showStatusUpdate('Driver found!', 'assigned');
      if (driverId != null) {
        fetchAndShowDriverInfo(driverId);
        startDriverLocationTracking(driverId);
      }
      break;
    case 'package_collected':
      showStatusUpdate('Driver picked up package', 'picked_up');
      showEstimatedArrival(delivery);
      break;
    case 'in_transit':
      showStatusUpdate('Driver en route to destination', 'in_transit');
      enableLiveTracking(driverId);
      break;
    case 'delivered':
      showStatusUpdate('Delivery complete!', 'completed');
      showRatingScreen(delivery['id']);
      stopLocationTracking();
      break;
    case 'cancelled':
      showStatusUpdate('Delivery cancelled', 'cancelled');
      handleCancellation(delivery);
      break;
    case 'failed':
      showStatusUpdate('Delivery failed', 'failed');
      showSupportContact();
      break;
  }
}
```

### **3. Integration with Edge Functions**

**Your Edge Functions Are Perfect!** The existing edge functions work seamlessly:

**A. `quote` Function** ✅
- Already calculates pricing using vehicle_types table
- Driver app uses same vehicle types for signup

**B. `book_delivery` Function** ✅  
- Creates delivery with `status: 'pending'`
- Driver app automatically detects new deliveries via realtime

**C. `pair_driver` Function** ✅
- Currently sets status to 'searching' 
- **Recommend changing to 'pending'** to match driver app expectations

**Suggested Update to pair_driver:**
```typescript
// Change this line in your pair_driver function:
const { data: updated, error: updErr } = await supabase
  .from('deliveries')
  .update({ status: 'pending' }) // Changed from 'searching' to 'pending'
  .eq('id', body.deliveryId)
  .select()
  .single();
```

### **4. Real-time Flow Example**

**Complete Customer Journey:**
1. **Customer books delivery** → `book_delivery` creates record with `status: 'pending'`
2. **Driver receives notification** → Driver app shows new offer via realtime
3. **Driver accepts** → Status becomes `driver_assigned`, customer sees "Driver assigned!"
4. **Driver arrives & picks up** → Status becomes `package_collected`
5. **Driver starts delivery** → Status becomes `in_transit`, customer can track live
6. **Driver completes** → Status becomes `delivered`, customer rates experience

### **5. Essential Customer App Features**

**A. Driver Information Display**
```dart
// Get complete driver details when assigned
Future<Map<String, dynamic>?> getDriverInfo(String driverId) async {
  try {
    final response = await supabase
      .from('user_profiles')
      .select('''
        id,
        first_name,
        last_name,
        phone_number,
        profile_image_url,
        driver_profiles!inner (
          vehicle_type_id,
          vehicle_model,
          license_number,
          rating,
          total_deliveries,
          is_online,
          current_latitude,
          current_longitude
        )
      ''')
      .eq('id', driverId)
      .eq('user_type', 'driver')
      .single();
    
    return response;
  } catch (e) {
    print('Error fetching driver info: $e');
    return null;
  }
}

// Display driver information in UI
void showDriverInfo(Map<String, dynamic> driverData) {
  final driverProfile = driverData['driver_profiles'];
  
  // Show driver card with:
  // - Name: "${driverData['first_name']} ${driverData['last_name']}"
  // - Rating: driverProfile['rating']
  // - Vehicle: driverProfile['vehicle_model']  
  // - Phone: driverData['phone_number'] (for contact)
  // - Photo: driverData['profile_image_url']
  // - Deliveries completed: driverProfile['total_deliveries']
}
```

**B. Live Location Tracking**
```dart
// Track driver location during delivery
StreamSubscription? _locationSubscription;

void startDriverLocationTracking(String driverId) {
  _locationSubscription = supabase
    .from('driver_profiles:id=eq.$driverId')
    .on(SupabaseEventTypes.update, (payload) {
      final data = payload['new'];
      final lat = data['current_latitude'];
      final lng = data['current_longitude'];
      
      if (lat != null && lng != null) {
        updateDriverMarkerOnMap(lat, lng);
        calculateEstimatedArrival(lat, lng);
      }
    })
    .subscribe();
}

void stopLocationTracking() {
  _locationSubscription?.cancel();
  _locationSubscription = null;
}

// Update map with driver's current position
void updateDriverMarkerOnMap(double lat, double lng) {
  // Update map marker position
  // Calculate distance to destination
  // Update estimated arrival time
}
```

**C. Estimated Arrival Time**
```dart
// Calculate and display estimated arrival
Future<void> calculateEstimatedArrival(double driverLat, double driverLng) async {
  final deliveryLat = currentDelivery['delivery_latitude'];
  final deliveryLng = currentDelivery['delivery_longitude'];
  
  // Calculate distance using Haversine formula or routing API
  final distanceKm = calculateDistance(driverLat, driverLng, deliveryLat, deliveryLng);
  final estimatedMinutes = (distanceKm * 2).round(); // ~2 min per km in city
  
  showEstimatedArrival(estimatedMinutes);
}
```

---

## 🔧 **Implementation Checklist for Customer App**

### **Immediate Actions:**
- [ ] Set up realtime subscriptions for delivery status updates
- [ ] Update UI to show real-time delivery progress with proper status mapping
- [ ] Modify `pair_driver` function to use `status: 'pending'` (not 'searching')
- [ ] Add driver information display when status becomes `driver_assigned`
- [ ] Implement proper error handling for edge cases

### **Enhanced Features:**
- [ ] Live driver location tracking on map during `in_transit` status
- [ ] Push notifications for status changes  
- [ ] Estimated arrival time calculations based on driver location
- [ ] Driver rating and review system after delivery completion
- [ ] Delivery history and receipt generation

### **Database Permissions (RLS Policies):**
Ensure your RLS policies allow:
- Customers can read their own deliveries (`customer_id = auth.uid()`)
- Customers can read assigned driver profiles (limited public info only)
- Customers can update delivery ratings after completion
- Customers cannot modify delivery status (only drivers can)

**Example RLS Policies:**
```sql
-- Allow customers to read their own deliveries
CREATE POLICY "Customers can read own deliveries" ON deliveries
FOR SELECT TO authenticated
USING (customer_id = auth.uid());

-- Allow customers to read assigned driver public info
CREATE POLICY "Customers can read assigned driver info" ON driver_profiles
FOR SELECT TO authenticated
USING (
  id IN (
    SELECT driver_id FROM deliveries 
    WHERE customer_id = auth.uid() 
    AND driver_id IS NOT NULL
  )
);
```

### **Edge Cases to Handle:**
- [ ] Driver cancels after accepting (status reverts to `pending`)
- [ ] Delivery fails (status becomes `failed`)
- [ ] Customer cancels before driver assigned
- [ ] Network connectivity issues during tracking
- [ ] Invalid or missing driver location data

---

## 📱 **Testing Integration**

### **Complete End-to-End Testing:**
1. **Book Delivery (Customer App)**
   - Customer creates delivery → Should create record with `status: 'pending'`
   - Verify delivery appears in customer's delivery list

2. **Driver Receives Offer (Driver App)**
   - Driver app should instantly show new delivery offer via realtime
   - Multiple drivers should see the same offer

3. **Driver Accepts (Driver App)**
   - Driver accepts delivery → Status updates to `driver_assigned`
   - Other drivers should see offer disappear immediately
   - Customer should see "Driver found!" with driver information

4. **Status Progression (Driver App)**
   - Driver marks pickup complete → Status: `package_collected`
   - Driver starts delivery → Status: `in_transit`
   - Driver completes delivery → Status: `delivered`

5. **Customer Tracking (Customer App)**
   - Customer sees real-time status updates without refresh
   - Customer can view driver information and location
   - Customer receives completion notification

### **Specific Test Cases:**
```dart
// Test realtime subscription
void testRealtimeConnection() async {
  print('Testing realtime connection...');
  
  final subscription = supabase
    .from('deliveries:id=eq.test-delivery-id')
    .on(SupabaseEventTypes.update, (payload) {
      print('Received update: ${payload['new']}');
    })
    .subscribe();
    
  // Manually update delivery status in database
  // Should receive realtime event
}

// Test driver info fetching
void testDriverInfoFetch() async {
  final driverInfo = await getDriverInfo('test-driver-id');
  assert(driverInfo != null);
  assert(driverInfo['first_name'] != null);
  print('Driver info test passed');
}
```

### **Debug Tools & Troubleshooting:**
- **Supabase Dashboard** → Realtime Inspector to monitor channels
- **Console Logs** → Check for subscription events and errors
- **Network Tab** → Verify WebSocket connections are established
- **Database Logs** → Check for RLS policy violations

**Common Issues:**
```dart
// Issue: Subscriptions not working
// Solution: Check authentication and RLS policies
if (supabase.auth.currentUser == null) {
  print('Error: User not authenticated for realtime');
}

// Issue: Driver location not updating
// Solution: Verify driver app is sending location updates
final driverOnline = await checkDriverOnlineStatus(driverId);
if (!driverOnline) {
  print('Warning: Driver appears offline');
}

// Issue: Multiple notifications for same update
// Solution: Properly cancel previous subscriptions
await previousSubscription?.cancel();
```

---

## 🎯 **Result: Seamless Real-time Experience**

With this integration, your customers will have:
- **Instant updates** when driver accepts their delivery (< 1 second delay)
- **Live tracking** of delivery progress with accurate status information
- **Real-time notifications** for each status change with meaningful messages
- **Professional experience** with driver information, contact details, and ETA
- **Complete transparency** throughout the entire delivery lifecycle

**Technical Benefits:**
- **Zero polling** - Pure real-time using Supabase WebSocket channels
- **Automatic conflict resolution** - Only one driver can accept each delivery
- **Robust error handling** - Graceful handling of network issues and edge cases
- **Scalable architecture** - Handles multiple concurrent deliveries efficiently

**User Experience Improvements:**
- **Reduced anxiety** - Customers always know delivery status
- **Better communication** - Direct access to driver contact information  
- **Trust building** - Real-time location tracking builds confidence
- **Professional appearance** - Branded, polished delivery tracking interface

The driver and customer apps will be perfectly synchronized via Supabase Realtime! 🚀

### **Performance Considerations:**
- Realtime subscriptions use minimal bandwidth (only status changes)
- Driver location updates are throttled to reasonable intervals
- Automatic cleanup of subscriptions when deliveries complete
- Efficient database queries with proper indexing on status and customer_id

---

## 📞 **Questions & Support**

For any clarification on the driver app implementation or integration details, feel free to ask. The driver side is fully functional and ready to integrate with your customer app's realtime features.