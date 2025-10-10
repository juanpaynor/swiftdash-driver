# Driver App Payload Formats - October 10, 2025

## 🚗 **Delivery Offer Payload Format**

### **1. Real-time Delivery Offer Subscription**

The driver app should listen for delivery offers using Supabase real-time subscriptions:

```dart
// Subscribe to delivery offers for this driver
supabase
  .from('deliveries')
  .stream(primaryKey: ['id'])
  .eq('driver_id', currentDriverId)
  .eq('status', 'driver_offered')
  .listen((data) {
    if (data.isNotEmpty) {
      final offer = data.first;
      showDeliveryOffer(offer);
    }
  });
```

### **2. Delivery Offer Payload Structure**

When a delivery is offered to a driver, the payload contains:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "customer_id": "customer-uuid-here",
  "driver_id": "driver-uuid-here",
  "vehicle_type_id": "vehicle-type-uuid",
  "status": "driver_offered",
  
  // Pickup Information
  "pickup_address": "123 Main St, Manila, Philippines",
  "pickup_latitude": 14.5995,
  "pickup_longitude": 120.9842,
  "pickup_contact_name": "John Doe",
  "pickup_contact_phone": "+639123456789",
  "pickup_instructions": "Building A, 2nd Floor",
  
  // Delivery Information  
  "delivery_address": "456 Oak Ave, Quezon City, Philippines",
  "delivery_latitude": 14.6760,
  "delivery_longitude": 121.0437,
  "delivery_contact_name": "Jane Smith", 
  "delivery_contact_phone": "+639987654321",
  "delivery_instructions": "Leave at reception desk",
  
  // Package Details
  "package_description": "Documents in envelope",
  "package_weight": 0.5,
  "package_value": 1000.00,
  
  // Pricing & Distance
  "distance_km": 15.2,
  "estimated_duration": 45,
  "total_price": 250.00,
  
  // Payment Info
  "payment_by": "sender",
  "payment_status": "pending",
  
  // Timing
  "created_at": "2025-10-10T10:30:00.000Z",
  "updated_at": "2025-10-10T10:35:00.000Z",
  "scheduled_pickup_time": null,
  
  // Optional fields
  "customer_rating": null,
  "driver_rating": null,
  "special_instructions": "Handle with care"
}
```

## 📱 **Driver App Implementation**

### **3. Accept/Decline Delivery API**

When driver accepts or declines an offer, call the `accept_delivery` Edge Function:

**Endpoint:** `POST /functions/v1/accept_delivery`

**Request Headers:**
```
Authorization: Bearer <driver_jwt_token>
Content-Type: application/json
```

**Request Payload:**
```json
{
  "deliveryId": "550e8400-e29b-41d4-a716-446655440000",
  "driverId": "driver-uuid-here",
  "accept": true
}
```

**Accept Response (success):**
```json
{
  "ok": true,
  "message": "Delivery accepted successfully",
  "delivery_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "driver_assigned"
}
```

**Decline Response (success):**
```json
{
  "ok": true,
  "message": "Delivery declined",
  "delivery_id": "550e8400-e29b-41d4-a716-446655440000", 
  "status": "pending"
}
```

**Error Response:**
```json
{
  "ok": false,
  "message": "Delivery is no longer available or not offered to this driver"
}
```

### **4. Driver App Flutter Implementation Example**

```dart
class DeliveryOfferService {
  static final supabase = Supabase.instance.client;
  
  // Listen for delivery offers
  static Stream<Map<String, dynamic>> listenForOffers(String driverId) {
    return supabase
      .from('deliveries')
      .stream(primaryKey: ['id'])
      .eq('driver_id', driverId)
      .eq('status', 'driver_offered')
      .map((data) => data.isNotEmpty ? data.first : {});
  }
  
  // Accept delivery offer
  static Future<Map<String, dynamic>> acceptDelivery({
    required String deliveryId,
    required String driverId,
    required bool accept,
  }) async {
    final response = await supabase.functions.invoke(
      'accept_delivery',
      body: {
        'deliveryId': deliveryId,
        'driverId': driverId,
        'accept': accept,
      },
    );
    
    if (response.status == 200) {
      return response.data as Map<String, dynamic>;
    } else {
      throw Exception('Failed to respond to delivery offer: ${response.data}');
    }
  }
}
```

### **5. UI Implementation Example**

```dart
class DeliveryOfferDialog extends StatelessWidget {
  final Map<String, dynamic> offer;
  final String driverId;
  
  const DeliveryOfferDialog({
    Key? key,
    required this.offer,
    required this.driverId,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final earnings = _calculateEarnings(offer['total_price']);
    
    return AlertDialog(
      title: Text('New Delivery Offer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Distance: ${offer['distance_km']}km'),
          Text('Estimated time: ${offer['estimated_duration']} min'),
          Text('Your earnings: ₱${earnings.toStringAsFixed(2)}'),
          SizedBox(height: 16),
          Text('Pickup: ${offer['pickup_address']}'),
          Text('Delivery: ${offer['delivery_address']}'),
          SizedBox(height: 16),
          Text('Package: ${offer['package_description']}'),
          if (offer['special_instructions'] != null)
            Text('Notes: ${offer['special_instructions']}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _respondToOffer(context, false),
          child: Text('Decline', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: () => _respondToOffer(context, true),
          child: Text('Accept'),
        ),
      ],
    );
  }
  
  double _calculateEarnings(double totalPrice) {
    // Driver gets 70% of total price (example)
    return totalPrice * 0.7;
  }
  
  Future<void> _respondToOffer(BuildContext context, bool accept) async {
    try {
      await DeliveryOfferService.acceptDelivery(
        deliveryId: offer['id'],
        driverId: driverId,
        accept: accept,
      );
      
      Navigator.of(context).pop();
      
      if (accept) {
        // Navigate to active delivery screen
        Navigator.pushNamed(context, '/active-delivery', 
          arguments: offer['id']);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
```

## 🔄 **Complete Workflow**

### **Driver App Flow:**
1. **Listen for offers** → Subscribe to deliveries with `status='driver_offered'` and `driver_id=currentDriverId`
2. **Show offer UI** → Display offer details with accept/decline buttons
3. **Send response** → Call `accept_delivery` Edge Function with accept/decline
4. **Handle result** → Navigate to active delivery or continue listening

### **System Flow:**
1. **Customer requests delivery** → Status: `'pending'`
2. **System finds driver** → Status: `'driver_offered'`, `driver_id` set
3. **Driver receives offer** → Real-time subscription triggers
4. **Driver accepts** → Status: `'driver_assigned'`, driver becomes unavailable
5. **Driver declines** → Status: `'pending'`, `driver_id` reset to null

## 🔧 **Troubleshooting**

### **Common Issues:**

1. **No offers received:**
   - Check driver is online: `is_online = true`
   - Check driver is available: `is_available = true`
   - Check location is updated: `current_latitude/longitude` not null
   - Verify real-time subscription is active

2. **Accept/Decline fails:**
   - Verify JWT token is valid and not expired
   - Check delivery is still in `'driver_offered'` status
   - Ensure `driverId` matches the offered driver

3. **Payload missing fields:**
   - Some fields may be null (like `scheduled_pickup_time`, ratings)
   - Check for null values before displaying in UI

### **Testing:**
```sql
-- Manually create a test offer
UPDATE deliveries 
SET status = 'driver_offered', 
    driver_id = 'your-driver-uuid-here',
    updated_at = NOW()
WHERE id = 'your-test-delivery-uuid';
```

## 📊 **Key Fields Summary**

### **Required for Driver UI:**
- `id` - Delivery ID for API calls
- `pickup_address`, `delivery_address` - Locations
- `pickup_latitude/longitude`, `delivery_latitude/longitude` - Map display
- `distance_km`, `estimated_duration` - Trip info
- `total_price` - Earnings calculation
- `package_description` - What to pick up

### **Optional but Useful:**
- `pickup_contact_name/phone` - Customer contact
- `delivery_contact_name/phone` - Recipient contact  
- `pickup_instructions`, `delivery_instructions` - Special notes
- `package_weight`, `package_value` - Package details
- `payment_by` - Who pays (sender/recipient)

**The driver app should handle all these fields gracefully, displaying available information and handling null values appropriately.** 🚗✨